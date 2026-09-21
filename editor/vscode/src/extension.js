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

/**
 * WP-22 (c)'s grace, in seconds, or 0 = never.
 *
 * IT IS NOT IN `settingValues`, DELIBERATELY: the server has no such
 * setting and nothing about this feature is on the wire. It is read here,
 * validated by `core.restartGraceSetting`, and used only by this file.
 *
 * A refusal is said OUT LOUD once per distinct problem -- the setting
 * decides whether we restart the user's language server, so a value that
 * was thrown away must not be discoverable only in the output channel --
 * and repeating it on every unrelated `ermine.*` edit would be noise.
 */
let warnedRestartSetting;

function restartGraceValue() {
  const result = core.restartGraceSetting(config().get("preview.restartAfterStuckSeconds", 0));
  reportSettingProblems(result.problems);
  const problem = result.problems.length ? result.problems[0] : undefined;
  if (problem && problem !== warnedRestartSetting) {
    warnedRestartSetting = problem;
    vscode.window.showWarningMessage("Ermine: " + problem);
  }
  if (!problem) warnedRestartSetting = undefined;
  return result.seconds;
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

/**
 * THE START EPOCH (delta review M2), and why it is not just the restart's.
 *
 * `startClient` AWAITS `warmClasspath`, which on a cold checkout runs sbt
 * for minutes behind a cancellable progress notification, and only after
 * that does it construct the client and assign the module global. A restart
 * that arrives inside that window used to find `client` already cleared,
 * skip the stop, and race into its OWN `startClient`: two clients, two
 * server JVMs, one of them referenced by nothing, never stopped, and with
 * its handlers still wired to these shared globals. Which one won was
 * decided by whichever warm-up finished last.
 *
 * So every attempt to bring a client up takes an epoch, `startClient`
 * re-checks it after every await and bails before constructing anything,
 * `restart` re-checks it after `startClient` and stops a stray if one
 * slipped through, and EVERY HANDLER a client registers checks it too: a
 * notification from a client that is no longer the current one must not
 * reach `applyStuck`, `applyGuard` or `applyRestart`.
 */
let startEpoch = 0;
/** The epoch of the client in `client`, so a stale client's events are ignored. */
let clientEpoch = 0;

async function startClient(context, epoch) {
  const mine = typeof epoch === "number" ? epoch : (startEpoch += 1);
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
  // CHECKPOINT (M2): the warm-up can take minutes. If anything asked for a
  // newer client while we were in it, this one must not exist at all --
  // nothing has been constructed yet, so bailing here is free.
  if (mine !== startEpoch) {
    log("start: superseded during the classpath warm-up — not starting this client");
    return;
  }

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

  const started = new LanguageClient("ermine", "Ermine Language Server", serverOptions, clientOptions);

  // The server reports boot progress and readiness through window/logMessage;
  // mirror it into the status bar so a 13s boot reads as progress, not a hang.
  started.onNotification("window/logMessage", (params) => {
    if (mine !== clientEpoch) return;               // M2: not the current client
    const message = String((params && params.message) || "");
    if (/ready/i.test(message)) {
      setStatus(`Ermine${fastModeSuffix()}`, message);
    } else if (/booting|Loading/i.test(message)) {
      setStatus("Ermine: starting session…", message);
    }
  });

  installPreviewHandlers(started, mine);

  // CURRENT FROM HERE, and before `start()`, so this client's own first
  // transitions are not thrown away by the epoch guards.
  client = started;
  clientEpoch = mine;

  setStatus("Ermine: starting session…", "Loading the Prelude/Layout closure (~13s)");

  // Deliberately not awaited by activate(): VS Code should never wait on the
  // handshake, let alone on the session boot behind it.
  started.start().then(
    () => log("language client started"),
    (err) => {
      log(`language client failed to start: ${err && err.stack ? err.stack : err}`);
      if (mine !== clientEpoch) return;             // M2: a newer client owns the status bar
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
 *
 * F1 OF THE WP-22(c) REVIEW: IT ALSO HANGS, AND A HANG IS NOT A THROW.
 * `client.stop()` is a promise that a wedged or half-dead server can leave
 * unsettled for ever, and a `try/catch` never sees that. Everything after
 * this call — clearing `client`, starting a new one, releasing the restart
 * guard — then waits for ever too. So the wait is BOUNDED, and when the
 * bound is reached we say so LOUDLY and carry on: a new server beside a
 * possibly-live old one is recoverable and visible; an editor whose Restart
 * command does nothing for the rest of the session is neither.
 *
 * The 5 s bound is not tuned, and cannot be from here: MEASURED, this
 * server answers a hover in 0.00 s while its preview is wedged (§2.5), and
 * `Preview.shutdown()` drains without joining the preview thread (READ), so
 * a healthy `shutdown`/`exit` is far under it. Whether `client.stop()` even
 * sends those, and whether it kills the process afterwards, is
 * `vscode-languageclient`'s own behaviour and is UNVERIFIED here.
 */
const STOP_TIMEOUT_MS = 5000;

async function stopQuietly(c, timeoutMs) {
  if (!c) return "none";
  const limit = typeof timeoutMs === "number" && timeoutMs > 0 ? timeoutMs : STOP_TIMEOUT_MS;
  // BOTH ARMS ARE HANDLED HERE, so a `stop()` that rejects AFTER the race
  // has been decided cannot surface as an unhandled rejection.
  const stopping = Promise.resolve()
    .then(() => c.stop())
    .then(
      () => "stopped",
      (err) => {
        log(`stop skipped (${err && err.message ? err.message : err})`);
        return "threw";
      }
    );
  let timer;
  const bounded = new Promise((resolve) => {
    timer = setTimeout(() => resolve("timed-out"), limit);
  });
  const outcome = await Promise.race([stopping, bounded]);
  clearTimeout(timer);
  if (outcome === "timed-out") {
    log(
      `stop: the language server did not stop within ${Math.round(limit / 1000)}s — carrying on anyway. ` +
        "THE OLD SERVER PROCESS MAY STILL BE ALIVE: check with `ps -ef | grep lsp.Main`, " +
        "and kill the older pid by hand if there are two."
    );
  }
  return outcome;
}

/**
 * TWO RESTARTS MUST NOT RUN AT ONCE (WP-22 (c)), AND THE USER'S MUST NEVER
 * BE THE ONE THAT IS REFUSED (review F1).
 *
 * Four callers reach this: the **Ermine: Restart Language Server** command
 * (which is also the button on our own stuck notification), a
 * `serverPath`/`logFile`/`maxHeap` change, the grace timer's fire, and the
 * command again while any of those is still running. Two interleaved
 * `stopQuietly`/`startClient` pairs would leave two clients and very
 * possibly two server processes behind, so they are serialised — but the
 * first build serialised them with a plain latch, and a `stop()` that never
 * settled left that latch true for ever and disabled the button for the
 * rest of the session, in exactly the situation the button exists for.
 *
 * SO: `core.restartAttempt` decides (pure, tested). The TIMER is refused
 * while anything is under way and reports that refusal back to the reducer
 * (D3). A USER restart always proceeds and SUPERSEDES: it mints a new
 * epoch, and the older run — which is sitting in a bounded `stopQuietly` —
 * abandons at its checkpoint instead of starting a second client. The
 * client is cleared BEFORE the await as well, so a superseding restart can
 * never stop the same client twice.
 */
/** `{source, epoch}` while a restart is under way, or null. */
let restartUnderway = null;

async function restart(context, source) {
  const who = source === core.RESTART_BY_TIMER ? core.RESTART_BY_TIMER : core.RESTART_BY_USER;
  const attempt = core.restartAttempt(restartUnderway, who);
  if (!attempt.proceed) {
    log(`restart: refused (${attempt.why})`);
    return attempt;
  }
  if (attempt.supersedes) log(`restart: ${attempt.why}`);
  // ONE COUNTER FOR BOTH (M2): a restart and the `startClient` it runs share
  // an epoch, so "superseded" means the same thing on both sides of the
  // await and a start that is still in its classpath warm-up can be told
  // that it has been.
  startEpoch += 1;
  const mine = startEpoch;
  restartUnderway = { source: who, epoch: mine };
  try {
    if (client) {
      log("restarting…");
      const going = client;
      // CLEARED BEFORE THE AWAIT: a superseding restart must not find this
      // client and stop it a second time.
      client = undefined;
      const outcome = await stopQuietly(going);
      // THE EDGE, SYNTHESISED (final re-check must-fix). On the timed-out
      // path the old client's real `Stopped` arrives after `clientEpoch`
      // has moved and is dropped as stale, and nothing else would ever
      // report it. Sent on every outcome -- see `onClientStopped` for why
      // that is safe and why guessing is not.
      onClientStopped(`the stop returned "${outcome}"`, "Running");
    }
    if (mine !== startEpoch) {
      log("restart: superseded by a newer one — not starting a second client");
      return attempt;
    }
    await startClient(context, mine);
    // AND AFTER (M2): `startClient` bails by itself if it is superseded
    // during its warm-up, but it can also be superseded AFTER it has put a
    // client up. Then that client is a stray -- nothing else will ever stop
    // it -- and the newer restart is bringing its own.
    if (mine !== startEpoch && client && clientEpoch === mine) {
      const stray = client;
      client = undefined;
      log("restart: a newer restart arrived after this one started a client — stopping the stray");
      await stopQuietly(stray);
    }
  } finally {
    if (restartUnderway && restartUnderway.epoch === mine) restartUnderway = null;
  }
  return attempt;
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
//
// WP-22 (c), THE RESTART, in one more paragraph. "The extension may
// restart" (the user). A wedged render leaves the preview stuck until the
// JVM hits -Xmx -- MEASURED at about two minutes after the watchdog fires,
// with the heap thrashing meanwhile -- and for a wedge that allocates
// nothing, for ever. So the extension arms a grace on the rising edge of
// the stuck state and, if nothing has come back when it expires, restarts
// its own language server through `restart(context)`. THE GRACE IS WHAT
// KEEPS Q10's RECOVERY: a slow-but-finite render answers `{stuck:false}`
// and disarms it. THE GUARD ABOVE IS WHAT KEEPS IT BOUNDED: every restart
// we cause is preceded by a mark, so the `Running` edge it produces asks
// instead of re-rendering, and a client-initiated `stop()` is (INFERRED,
// UNVERIFIED) not counted by the library's crash limiter, which makes the
// guard the only bound there is. `ermine.preview.restartAfterStuckSeconds`
// DEFAULTS TO 0 = NEVER. NOTHING HERE HAS BEEN OBSERVED IN A REAL EDITOR BY
// ANYONE.

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
/**
 * The last answer a SERVER gave, which is not always what is on screen: a
 * params refusal (WP-8 S2) is shown in the tab but was decided here, and the
 * Q11 watcher's question -- "is the picked report sitting on a PLACEMENT
 * 404?" -- is about the server's view and nothing else (S2 review nit 5).
 */
let lastServerAnswer;
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
 * D3 (delta re-review): WHAT THE USER LAST ANSWERED "Not now" TO, as
 * `core.heldPromptToken`'s string, or undefined.
 *
 * Without it, format-on-save asks once per save: the params file is
 * rewritten, the fingerprint does not move, the mark stands, and the
 * question comes back. With it, the same question for the same mark and the
 * same parameters is asked ONCE; the `held` status bar keeps saying so, and
 * each suppressed re-ask is one line in the channel rather than a
 * notification. Anything that changes the situation -- a new mark (a fresh
 * `at`), another pick, parameters that really moved (which clears the mark),
 * or the user rendering it themselves -- produces a different token, or no
 * mark at all, and the question comes back.
 *
 * **IT IS IN-PROCESS ONLY, DELIBERATELY.** Unlike the mark itself it is not
 * mirrored into `workspaceState`, so reloading the window asks once more.
 * That is the safe side: the mark IS restored, so the report is still held,
 * and one question after a reload is cheaper than persisting a refusal the
 * user may not remember giving.
 */
let heldRefusedToken;
/**
 * WP-22 (c): the grace timer's state, and the timer itself.
 *
 * `restartState` is `core.restartReduce`'s -- the seconds, the live arm's
 * SERIAL, the stuck/running mirror and the floor's memory of the last fire.
 * `restartTimer` is the only clock: the reducer holds none, and the expiry
 * comes back to it as an event carrying the serial it was armed with, so a
 * timer left over from an earlier incident cannot fire.
 *
 * `lastFireAt` lives in `restartState` and therefore survives our own
 * restarts -- the extension host is not reloaded by them -- which is what
 * makes the floor a real bound rather than a per-incident one.
 */
let restartState = core.initialRestartState(0);
let restartTimer;
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
/**
 * HOW MANY TIMES THE LANGUAGE CLIENT HAS BEEN SEEN TO STOP (S2 review M5).
 *
 * `clientEpoch` moves only when WE build a new client. `clientOptions`
 * configures no `errorHandler` and no `maxRestartCount`, so
 * `vscode-languageclient`'s DEFAULT close action applies and may restart the
 * server process on the SAME client object -- and then a render whose file
 * read spans that restart would see the same pick, the same generation and
 * the same epoch, and would reach the fresh process WITHOUT passing WP-22's
 * one consultation site. THE LIBRARY'S BEHAVIOUR HERE IS UNVERIFIED (its
 * source is unread, per the project rule, and nobody has run this
 * extension), so this counter is a DEFENCE, not a fix for a measured bug: it
 * costs one integer and closes the hole whichever way the library behaves.
 */
let stopCount = 0;
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
 * WP-8 S2. THE PARAMS ACTUALLY SENT on the last render, or `undefined` if
 * none has been sent yet -- which is what the wedge mark carries, so that
 * changing the parameters CLEARS the mark instead of minting a second one
 * (WP-22's `paramsFingerprint`, whose hook this is).
 *
 * `null` IS A VALUE: a params file holding `null` is what a `Maybe`-rooted
 * report wants, so "nothing has been sent" cannot be spelled `null`.
 */
let lastParamsSent;
/**
 * WP-8 S2: what we have already said about THIS pick's params file, so that
 * "one line per distinct problem" is one line and not one per render -- a
 * save-driven loop renders every few seconds and a repeated sentence in the
 * channel is how a real message gets missed. Cleared on a pick change, and
 * the `missing` entry is dropped again whenever a file IS read, so a file
 * that is deleted a second time is announced a second time.
 */
let paramsNotices = new Set();
/**
 * U5: the credential warning is once per FILE per session, not per pick and
 * not per render. It survives a pick change deliberately -- the hazard is a
 * property of the file, and re-warning about the same file when the developer
 * comes back to that report is noise they will learn to dismiss.
 */
const warnedCredentialFiles = new Set();

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
  // Nothing is shown after a teardown, and the item may already be disposed.
  if (previewDisposed) return;
  const view = core.statusBarState({
    stuck: stuckState.stuck,
    message: stuckState.message,
    running: stuckState.running,
    rendering: renderInFlight,
    pick: picked,
    mark: wedgeMark,
    // WP-22 (c): 0 unless a grace is armed, which with the default setting
    // of 0 is always.
    restartIn: core.restartArmedSeconds(restartState),
    // What the user ASKED for, so a grace the floor stretched can say why
    // it is longer than that.
    restartAsked: restartState.seconds,
    // D3 and N2: why the automatic restart did not happen, and whether the
    // server the user is looking at came back because WE restarted it.
    restartProblem: core.restartProblem(restartState),
    restartedByUs: core.restartedByUs(restartState),
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

// ------------------------------------------------- params files (WP-8, S2)
//
// A report's parameters are an ordinary committed file,
// `<workspace folder>/.ermine/preview/<Module>/<binding>.params.json`
// (section 6). S2 READS ONE AND SENDS IT. It writes nothing -- no skeleton,
// no `<binding>.schema.json`, no `.gitignore`, and it asks for no schema:
// that is S3. Everything decidable from data alone is in `preview-core.js`;
// what is here is the disk, the watcher and the notifications.
//
// IT READS THE FILE FROM DISK, NOT FROM THE EDITOR BUFFER (section 2.4: the
// preview "reads saved files, not buffers"), through `vscode.workspace.fs`,
// which is why every render's send path now has an `await` in it that was
// not there before -- see `core.mayStillSend` for what that costs and how it
// is paid.

/** Every workspace folder's own path, for `core.paramsFolderFor` (G1). */
function workspaceFolderPaths() {
  const folders = vscode.workspace.workspaceFolders;
  const out = [];
  for (const folder of folders || []) {
    const p = folder && folder.uri && folder.uri.fsPath;
    if (typeof p === "string" && p) out.push(p);
  }
  return out;
}

/**
 * Where THIS pick's params file would live, or the named reason it has none.
 *
 * THE FOLDER IS THE ONE THAT CONTAINS THE REPORT, never `folders[0]` (G1):
 * `rootsFor` falls back to the first folder for a SETTING, which is
 * defensible, and doing the same for a FILE would read -- and later write --
 * inside an unrelated repository that happens to be first in the window.
 */
function paramsPathsFor(pick) {
  if (!pick) return core.paramsPaths(pick, undefined);
  return core.paramsPaths(pick, core.paramsFolderFor(pick.fsPath, workspaceFolderPaths()));
}

/** One channel line per distinct params problem per pick, and no more. */
function paramsNoticeOnce(pick, reason, line) {
  const key = core.paramsNoticeKey(pick, reason);
  if (paramsNotices.has(key)) return false;
  paramsNotices.add(key);
  log("preview: " + line);
  return true;
}

/**
 * A pick change -- or learning the module name, which MOVES the params
 * directory -- makes every earlier notice about a different file.
 * `lastParamsSent` is NOT cleared here: it is what the wedge mark compares
 * against, and it is reset only where the pick itself changes.
 */
function forgetParamsNotices() {
  paramsNotices = new Set();
}

/**
 * THE READ ITSELF, and the only place S2 touches the disk.
 *
 * `vscode.workspace.fs.readFile` rather than `fs.readFileSync`, for ONE
 * reason: it is asynchronous, which is what the extension host wants. The
 * bytes are decoded as UTF-8 here and the BOM is `paramsToSend`'s problem
 * (review I-2), because the byte CAP has to count the BOM.
 *
 * **THIS IS LOCAL WORKSPACES ONLY, AND THE CLAIM THAT IT WAS NOT IS
 * WITHDRAWN (S2 review M7).** `vscode.Uri.file(fsPath)` DISCARDS the scheme
 * and the authority, so on a `vscode-remote:` or a virtual workspace this
 * addresses a local path that does not exist -- `workspace.fs` is the right
 * API and it is being handed the wrong Uri. The whole extension is
 * `fsPath`-based (the pick, `paramsPaths`, `shouldRerenderOnParamsSave`,
 * `rootsFor`, and the server it spawns is a local process), so making this
 * one call remote-correct would fix nothing by itself; doing it properly
 * means carrying the workspace folder's OWN `Uri` through the pick and
 * joining with `Uri.joinPath`, which is a ticket and not a line. Recorded as
 * a stated limitation in section 6 rather than pretended away.
 */
async function readParamsFile(fsPath) {
  const bytes = await vscode.workspace.fs.readFile(vscode.Uri.file(fsPath));
  return Buffer.from(bytes).toString("utf8");
}

/**
 * The file's size WITHOUT reading it, or null when the provider cannot say.
 * A `stat` that throws is not an error here: the read that follows will
 * produce the real one, and a provider with no `stat` must still work.
 */
async function paramsFileSize(fsPath) {
  try {
    const st = await vscode.workspace.fs.stat(vscode.Uri.file(fsPath));
    return st && typeof st.size === "number" ? st.size : null;
  } catch (err) {
    return null;
  }
}

/**
 * A READ THAT NEVER SETTLES IS NOT A READ THAT THREW -- `stopQuietly`'s own
 * lesson (WP-22(c) review F1), applied to the new await (S2 review nit 7).
 * Both arms of the race are handled, so a read that rejects after the bound
 * cannot surface as an unhandled rejection.
 */
async function readParamsFileBounded(fsPath, ms) {
  const limit = typeof ms === "number" && ms > 0 ? ms : core.PARAMS_READ_TIMEOUT_MS;
  let timer;
  const bounded = new Promise((resolve) => {
    timer = setTimeout(() => resolve({ timedOut: true }), limit);
  });
  const reading = Promise.resolve()
    .then(() => readParamsFile(fsPath))
    .then((text) => ({ text }), (err) => ({ err }));
  const outcome = await Promise.race([reading, bounded]);
  clearTimeout(timer);
  return outcome;
}

/**
 * THE PARAMS FOR ONE RENDER, as data: `{params}` or `{refusal}`, plus what
 * the glue should SAY about it. Nothing is logged or shown from in here --
 * the caller emits after `core.mayStillSend` has agreed the render is still
 * the current one, so a notification can never describe a report the user
 * has already moved away from.
 *
 * THE FOUR OUTCOMES (section 6's own list):
 *   no params FILE                -> `{}`, exactly what WP-7 sends today,
 *                                    said once per pick;
 *   a `paramsPaths` PROBLEM       -> `{}`, said once per distinct reason;
 *   a `paramsToSend` PROBLEM      -> a REFUSAL: the render does not happen
 *                                    (G7), and the tab shows why;
 *   a read error that is NOT "no   -> a REFUSAL too, and this is S2's own
 *   such file"                       decision: rendering `{}` over a params
 *                                    file that exists but could not be read
 *                                    would show a document that looks right
 *                                    and is not, which is exactly why S1
 *                                    made an EMPTY file a refusal rather
 *                                    than `{}`.
 */
async function prepareParams(pick) {
  const paths = paramsPathsFor(pick);
  if (paths.problem) {
    return { params: {}, notice: { reason: paths.problem.reason, line: paths.problem.message } };
  }
  // THE CAP, BEFORE THE FILE IS MATERIALISED (review nit 3): `readFile`
  // pulls the whole thing into the extension host, and a 1 GiB params file
  // would kill the host the way a 64 MiB frame kills the server.
  const tooBig = core.paramsTooLargeToRead(await paramsFileSize(paths.paramsPath));
  if (tooBig) return { path: paths.paramsPath, refusal: tooBig };

  const outcome0 = await readParamsFileBounded(paths.paramsPath);
  if (outcome0.timedOut) {
    return { path: paths.paramsPath, refusal: core.paramsReadTimedOut(paths.paramsPath) };
  }
  if (outcome0.err) {
    const err = outcome0.err;
    if (core.meansFileMissing(err)) {
      return {
        params: {},
        path: paths.paramsPath,
        notice: { reason: "missing", line: core.paramsMissingNotice(paths.paramsPath) },
      };
    }
    return {
      path: paths.paramsPath,
      refusal: {
        reason: "unreadable",
        message: 'The params file "' + paths.paramsPath + '" exists but could not be read (' +
                 (err && err.message ? err.message : String(err)) + "), so the report was NOT rendered: " +
                 "rendering it with empty parameters would show a document that looks right and is not.",
      },
    };
  }
  const outcome = core.paramsToSend(outcome0.text);
  if (outcome.problem) return { path: paths.paramsPath, refusal: outcome.problem };
  return { params: outcome.params, warnings: outcome.warnings, path: paths.paramsPath, read: true };
}

/**
 * THE `Stopped` EDGE, IN ONE PLACE, because it now has TWO sources (final
 * re-check must-fix).
 *
 * The epoch guard that fixed M2 also drops a LEGITIMATE edge on one path:
 * when `stopQuietly` hits `STOP_TIMEOUT_MS`, `restart` carries on,
 * `startClient` moves `clientEpoch`, and the old client's LATE `Stopped` is
 * then dropped as stale. Nothing else ever reports it, so `stuckReduce`
 * never leaves `running: true`, the new client's `Running` produces
 * `rerender: false`, and WP-22's ONE CONSULTATION IS NEVER REACHED: no held
 * question, no offline status, no `died-mid-render` mark, and `lastAnswer`
 * -- an answer from a process that is gone -- survives into the new one. It
 * failed safe (nothing auto-rendered) and it was still wrong.
 *
 * So `restart()` SYNTHESISES the edge itself after every stop attempt, and
 * both callers run this one function rather than two copies of it.
 *
 * **IT IS SENT UNCONDITIONALLY, and that is the decision.** The alternative
 * -- send it only when the outcome was not a clean "stopped" -- needs the
 * extension to know whether the library emitted the edge, which is exactly
 * the thing that is UNVERIFIED here (its source is unread, and nobody has
 * run this extension). Sending it always removes that guess, and costs
 * nothing, because everything it touches is idempotent for a second
 * `Stopped`: `guardReduce`'s SET is idempotent per key (and by then
 * `inFlightRender` is usually already null, so it does not even set);
 * `restartReduce` sets `running: false` and disarms, both no-ops the second
 * time; `stuckReduce` gates its `offline` effect on `s.running`, so only
 * the FIRST of the two logs or changes the status bar; and
 * `lastAnswer = undefined` is idempotent by construction.
 */
function onClientStopped(why, from) {
  log(`preview: the language server stopped (${why})`);
  // M5: bumped on EVERY stop, including one the library performs by itself
  // on the same client object, which `clientEpoch` cannot see.
  stopCount += 1;
  // WP-22: the server died while a render of the pick was in flight. It may
  // never have fired the watchdog -- at a small -Xmx the JVM exits first
  // (MEASURED, section 2.5: WpBlow at 256m, exit 3 at 8.6 s, no fire). M1:
  // `inFlightRender` -- unlike `renderInFlight` -- is NOT cleared by the
  // rejection that this same death causes, so this does not depend on which
  // of the two the library delivers first, and `renderNow`'s catch marks it
  // too.
  applyGuard(
    core.guardReduce(wedgeMark, {
      type: "clientState",
      to: "Stopped",
      renderInFlight: inFlightRender !== null,
      pick: core.markPickFor(inFlightRender && inFlightRender.pick, picked),
      // WP-8: the mark carries the params that were in force, so that
      // changing them later CLEARS it rather than minting a second one.
      params: core.markParamsFor(inFlightRender ? inFlightRender.params : undefined, lastParamsSent),
      at: Date.now(),
    })
  );
  applyRestart(core.restartReduce(restartState, core.restartEvents.clientState("Stopped")));
  applyStuck(
    core.stuckReduce(stuckState, { type: "clientState", from: from, to: "Stopped" }),
    core.TRIGGER_RESTART
  );
}

function installPreviewHandlers(c, epoch) {
  // M2 (delta review): EVERY handler below belongs to ONE client, and a
  // client that is no longer the current one must not reach the reducers.
  // Without this a stray client -- one started while another restart was in
  // its classpath warm-up -- keeps feeding `applyStuck`, `applyGuard` and
  // `applyRestart` from a server nothing references any more.
  const mine = typeof epoch === "number" ? epoch : clientEpoch;
  const stale = () => mine !== clientEpoch;

  // Section 3 step 5-6. The set already includes dependents, so saving a
  // widget module names every report that imports it.
  c.onNotification("ermine/preview/invalidated", (params) => {
    if (stale()) return;
    const modules = params && Array.isArray(params.modules) ? params.modules : [];
    if (!picked) return;
    // WP-22: the server's own dependency closure is the exact "the report's
    // inputs changed" signal, so it clears the wedge mark (T3 is never
    // suppressed -- the notification IS the evidence).
    applyGuard(core.guardReduce(wedgeMark, { type: "invalidated", modules, pick: picked }));
    if (core.shouldRerenderOnInvalidated(picked, modules)) {
      scheduleRender(`invalidated: ${picked.module}`, core.TRIGGER_INVALIDATED);
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
    if (stale()) return;
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
        params: core.markParamsFor(inFlightRender ? inFlightRender.params : undefined, lastParamsSent),
        at: Date.now(),
      })
    );
    // WP-22 (c), and BEFORE `applyStuck`: the rising edge arms the grace,
    // the falling one disarms it (Q10's recovery), and the notification
    // `applyStuck` is about to show has to be able to say so.
    applyRestart(core.restartReduce(restartState, core.restartEvents.notification(event.stuck, applies, Date.now())));
    applyStuck(core.stuckReduce(stuckState, event), core.TRIGGER_RECOVERED);
  });

  // Section 5's "Server stopped" row, and DD-2's `seq` reset. The library
  // passes through `Starting`, so "Stopped -> Running" is observed as any
  // transition INTO Running.
  if (typeof c.onDidChangeState === "function") {
    c.onDidChangeState((event) => {
      const from = CLIENT_STATE[event && event.oldState] || String(event && event.oldState);
      const to = CLIENT_STATE[event && event.newState] || String(event && event.newState);
      const dropped = stale();
      // EVERY transition is logged, dropped ones included, with the client's
      // epoch (final re-check). Whether a fresh `LanguageClient` emits an
      // initial `Stopped -> Starting` at all is *external* and UNVERIFIED --
      // nobody has run this extension -- and this line is what lets a human
      // settle it while ticking the manual checklist.
      log(`client ${mine}: state ${from} -> ${to}${dropped ? " (DROPPED: a newer client is current)" : ""}`);
      if (dropped || !CLIENT_STATE[event && event.newState]) return;
      if (to === "Stopped") {
        onClientStopped("the language client reported it", from);
        return;
      }
      if (to === "Running" && !stuckState.running) {
        // A fresh process knows nothing about the last one: the answer we
        // are holding described a server that is gone.
        lastAnswer = undefined;
        lastServerAnswer = undefined;
      }
      // WP-22 (c): the client leaving Running for ANY reason disarms the
      // grace -- the server died by itself, or the user restarted it, or we
      // did -- and entering Running disarms it too, because `stuckReduce`
      // resets the stuck state for the fresh process.
      applyRestart(core.restartReduce(restartState, core.restartEvents.clientState(to)));
      applyStuck(
        core.stuckReduce(stuckState, { type: "clientState", from, to }),
        core.TRIGGER_RESTART
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
    // WP-22 (c): when a grace is armed the notification says so, and says
    // which setting turns it off. The button below does the same thing
    // sooner, and stays exactly as it was.
    vscode.window
      .showErrorMessage(
        core.stuckNotificationText(
          stuckState.message,
          core.restartArmedSeconds(restartState),
          restartState.seconds
        ),
        "Restart Language Server"
      )
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
    // THE SAME FUNCTION THE SEND POINT ASKS (D1/D2 of the delta re-review).
    // No `scheduledAt` here on purpose: the render is being scheduled at
    // this instant, so "was the mark minted after it was scheduled" is
    // vacuous and `mayAutoRender` degrades to the consultation alone.
    const permitted = core.mayAutoRender(wedgeMark, picked, trigger);
    if (permitted.render) {
      scheduleRender(
        trigger === core.TRIGGER_RESTART ? "the language server restarted" : "the preview recovered",
        trigger === core.TRIGGER_RESTART ? core.TRIGGER_RESTART : core.TRIGGER_RECOVERED
      );
    } else {
      log("preview: not re-rendering — " + permitted.why);
      holdRender(trigger);
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
function holdRender(trigger) {
  const message = core.heldMessage(wedgeMark, picked, core.restartedByUs(restartState));
  if (!message) return;              // a mark that is not this pick's is never consulted
  log("preview: HELD — " + message);
  // D3: the same question, for the same mark and the same parameters, is
  // asked ONCE. A RESTART always asks again -- the user pressed the button
  // or the server died, and either is a new event the user did not cause by
  // saving a file -- and so do the other unconfirmed triggers; only a params
  // save is remembered, because a formatter can repeat it every few seconds.
  const asking = core.shouldAskHeld(heldRefusedToken, wedgeMark, picked, trigger);
  if (!asking.ask) {
    log("preview: not asking again — " + asking.why);
    return;
  }
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
      // D3: remember WHAT was refused, so a formatter cannot ask again for
      // the same mark and the same parameters. `asking.token` is the mark's
      // identity as it was when the question was SHOWN.
      heldRefusedToken = asking.token;
      return;
    }
    if (verdict.why) log(`preview: rendering anyway (${verdict.why})`);
    heldRefusedToken = undefined;                        // consent resets it
    applyGuard(core.guardReduce(wedgeMark, { type: "render", explicit: true }));
    renderNow("Render anyway", true, core.TRIGGER_EXPLICIT).catch((err) =>
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
 * WP-22 (c)'s GLUE, and the only clock in the feature.
 *
 * `core.restartReduce` decides; this arms and cancels the one `setTimeout`,
 * says what happened in the channel, and -- on a fire -- does the two
 * things the decision cannot do for itself: make sure the guard has a mark
 * for the pick that wedged, and call `restart(context)`.
 */
function applyRestart(result) {
  restartState = result.state;
  const fx = result.effects;
  // DELTA REVIEW M1: the reducer says BUG when this file hands it an event
  // that is missing something only this file can supply. It is loud on
  // purpose -- the defect it names cost a whole feature silently.
  if (fx.bug) log("preview: BUG — " + fx.bug);
  if (fx.disarm) {
    clearRestartTimer();
    log("preview: the automatic restart is disarmed (" + fx.why + ")");
  }
  if (fx.arm) {
    // `ms` is the exact delay and `seconds` is what the user is told; they
    // differ when the floor stretched this arm (review D2).
    armRestartTimer(fx.serial, fx.ms);
    log(`preview: the language server will be restarted in ${fx.seconds}s unless the preview recovers (${fx.why})`);
  }
  if (fx.refused) {
    // D3: a refusal is not a log line. The status bar's stuck tooltip
    // carries it too, and the user is told once, without a button.
    log("preview: the automatic restart did NOT happen (" + fx.why + ")");
    vscode.window.showWarningMessage(
      "Ermine: the preview is stuck and the automatic restart did not happen — " + fx.why +
        '. Run "Ermine: Restart Language Server" when you are ready.'
    );
  }
  if (fx.fire) fireRestart(fx);
  else if (fx.why && !fx.arm && !fx.disarm && !fx.refused) log("preview: the restart timer fired and did nothing (" + fx.why + ")");
  setPreviewStatus();
}

function clearRestartTimer() {
  if (restartTimer) {
    clearTimeout(restartTimer);
    restartTimer = undefined;
  }
}

/**
 * The expiry goes back to the reducer as an EVENT carrying the serial this
 * arm was minted with, so a timer that survived its disarm -- already
 * queued when the cancel ran, or simply missed -- is recognised as stale
 * and does nothing.
 */
function armRestartTimer(serial, ms) {
  clearRestartTimer();
  restartTimer = setTimeout(() => {
    restartTimer = undefined;
    applyRestart(core.restartReduce(restartState, core.restartEvents.expiry(serial, Date.now())));
  }, Math.max(0, ms));
}

/**
 * THE RESTART ITSELF, AND THE RULE THAT MAKES IT SAFE: it never happens
 * without a mark.
 *
 * The restart we cause produces exactly the `Stopped` then `Running` edges
 * a crash produces, and the `Running` edge asks for a re-render of the
 * current pick (`stuckReduce`'s `rerender: !s.running`). WP-22 (a)+(b)
 * turn that into a question instead -- but only for a pick that is MARKED.
 * So the mark is set HERE, before anything is stopped, and if the wedge
 * cannot be attributed to a pick at all the restart does not happen: a
 * restart nothing would hold is the loop this whole ticket exists to close.
 */
function fireRestart(fx) {
  // D3: EVERY EXIT FROM HERE TELLS THE REDUCER WHAT HAPPENED. Only a
  // restart that actually started may move the floor's memory, and a
  // refusal has to reach something the user looks at.
  const refuse = (why) => {
    log("preview: NOT restarting the language server — " + why);
    applyRestart(core.restartReduce(restartState, core.restartEvents.fireRefused(why, Date.now())));
  };
  // N2's rule: the render that is in flight is the better claim about what
  // wedged; the current pick is the fallback.
  const pick = core.markPickFor(inFlightRender && inFlightRender.pick, picked);
  if (!pick) {
    refuse(
      "nothing is picked and no render is in flight, so the wedge cannot be attributed to a report " +
        "and nothing would hold the re-render afterwards"
    );
    return;
  }
  if (!extContext) {
    refuse("there is no extension context to start a client with");
    return;
  }
  // F1: the timer never stacks on a restart that is already under way, and
  // it asks the same pure function `restart` asks, so the two agree.
  const attempt = core.restartAttempt(restartUnderway, core.RESTART_BY_TIMER);
  if (!attempt.proceed) {
    refuse(attempt.why);
    return;
  }
  // "killed-by-us" ONLY IF NOTHING ELSE GOT THERE FIRST: `guardReduce`'s
  // SET is idempotent per key, so a pick already marked "watchdog" or
  // "died-mid-render" keeps that reason and its own `at`.
  applyGuard(
    core.guardReduce(wedgeMark, {
      type: "killedByUs",
      pick,
      params: core.markParamsFor(inFlightRender ? inFlightRender.params : undefined, lastParamsSent),
      at: Date.now(),
    })
  );
  if (!core.markMatches(wedgeMark, pick)) {
    refuse(
      "the wedge mark could not be set for " + core.pickLabel(pick) +
        ", and a restart with no mark re-renders the report that wedged"
    );
    return;
  }
  // A render coalesced against the server we are about to stop has no
  // meaning any more, and it would reach the FRESH server without passing
  // the one consultation site.
  if (coalesceTimer) {
    clearTimeout(coalesceTimer);
    coalesceTimer = undefined;
  }
  log(
    `preview: RESTARTING the language server — ${fx.why} ` +
      `(ermine.preview.restartAfterStuckSeconds = ${fx.seconds}; ${core.pickLabel(pick)} is held)`
  );
  // The floor's memory moves HERE, and only here: the restart has started.
  applyRestart(core.restartReduce(restartState, core.restartEvents.fired(Date.now())));
  restart(extContext, core.RESTART_BY_TIMER).catch((err) =>
    log(`preview: the automatic restart failed: ${err && err.stack ? err.stack : err}`)
  );
}

/**
 * M1: the latch is released by THIS render's own settled result, and only
 * by that one -- `renderNow` is re-entrant, so a slower render's
 * continuation must not release a newer render's latch.
 */
function releaseInFlight(generationOfThisRender) {
  if (inFlightRender && inFlightRender.generation === generationOfThisRender) inFlightRender = null;
}

function scheduleRender(reason, trigger) {
  if (!picked) return;
  if (coalesceTimer) clearTimeout(coalesceTimer);
  // WHEN THE EVIDENCE ARRIVED (delta re-review, families B and C). A render
  // can sit here for 150 ms and then in its params read while the report
  // wedges the server AGAIN; `core.mayAutoRender` compares this against the
  // mark's own `at`, so a change that was real when it was scheduled is not
  // treated as evidence about a server that has since wedged.
  //
  // IT IS TAKEN ON EVERY CALL, so it is LAST-WINS exactly as the trigger is,
  // and the two therefore come from the SAME call and cannot describe
  // different events. FIRST-WINS was not chosen: it would date the render by
  // an event the window has since superseded, so a mark minted between the
  // first and the last trigger would look older than the render and the hold
  // would not fire -- the opposite of what this is for.
  const scheduledAt = Date.now();
  coalesceTimer = setTimeout(() => {
    coalesceTimer = undefined;
    // THE TRIGGER TRAVELS WITH THE REASON, because the consultation at the
    // end of `renderNow` asks WHICH trigger is rendering, not what it would
    // print (S2 review M6).
    //
    // **LAST WINS INSIDE THE WINDOW, AND THE RULE THAT MAKES THAT SOUND IS
    // D1's** (delta re-review): every trigger that is NOT in
    // `UNCONFIRMED_TRIGGERS` has already cleared the mark by the time it
    // schedules -- that is exactly the membership rule -- so a window whose
    // last event is an evidence trigger has a cleared mark, and one whose
    // last event is unconfirmed consults it. Before D1, `roots` broke that:
    // it could arrive last, with the mark standing, and be permitted.
    // Keeping the most CONSERVATIVE label instead would change nothing
    // under the rule and would hide which event actually asked for the
    // render, which is what the channel line is for.
    renderNow(reason, false, trigger, scheduledAt)
      .catch((err) => log(`preview: render failed: ${err && err.stack ? err.stack : err}`));
  }, COALESCE_MS);
}

async function renderNow(reason, reveal, trigger, scheduledAt) {
  if (!picked) return;
  if (!client) {
    log("preview: no language client — nothing to render with");
    return;
  }
  // D2: a trigger nothing declared is a BUG, said out loud, and is then
  // treated as bringing NO evidence of change -- `shouldAutoRender` fails
  // CLOSED on it. It used to fail open, and a mutant that simply forgot to
  // forward the trigger through the coalescer neutered both consultation
  // sites for every automatic render and survived the whole suite.
  const triggerBug = core.triggerProblem(trigger);
  if (triggerBug) log("preview: BUG — " + triggerBug);
  generation += 1;
  // ONE SNAPSHOT, TAKEN BEFORE THE READ, AND THE ONLY THING THE REST OF THIS
  // FUNCTION READS (S2 review M1 and M2). It COPIES the pick, roots array
  // included, because the roots handler mutates `picked.roots` IN PLACE --
  // which made the `roots-changed` arm compare an array with itself and
  // never fire. And because it is built HERE, before the await, there is no
  // object literal after the await in which a captured value can be swapped
  // for the live global without the swap being visible.
  const attempt = core.renderAttempt(generation, picked, clientEpoch, stopCount, stuckState.highWater);
  const mine = attempt.generation;
  // PER REQUEST, not a module global (review S2): `renderNow` is re-entrant
  // and a second render must not rewrite the first one's mark. N2: the pick
  // this request is ABOUT is the snapshot's, so a stuck answer arriving a
  // minute later cannot mark whatever is current then.
  const sentAtMark = attempt.seqAtSend;
  const sentPick = attempt.pick;
  // The spinner starts now -- reading a file IS this render working -- but
  // the WEDGE LATCH is NOT taken here: nothing is on the wire yet, and a
  // render that never gets sent must not be able to mark a report as having
  // died mid-render. It is taken immediately before `sendRequest`.
  renderInFlight = true;
  setPreviewStatus();

  // ------------------------------------------------ WP-8 S2: the params
  //
  // THE GENERATION IS TAKEN BEFORE THE READ, and that is deliberate: this
  // render supersedes whatever was in flight the moment it is decided on, so
  // an older answer landing during the read is discarded rather than
  // overwriting what this one is about to show (including a refusal).
  let prepared;
  try {
    prepared = await prepareParams(sentPick);
  } catch (err) {
    // `prepareParams` handles the read's own failures; this covers the
    // shapes nothing here can anticipate (the editor's file system API
    // missing, a Uri it will not build). It must not escape: an exception
    // out of `renderNow` would leave the spinner running for ever, and
    // "release whatever was taken" is the whole discipline of this path.
    prepared = {
      refusal: {
        reason: "unreadable",
        message: "The parameters could not be prepared (" +
                 (err && err.message ? err.message : String(err)) + "), so the report was not rendered.",
      },
    };
  }

  // THE ASYNC GAP. Everything the snapshot holds could have moved under us;
  // `core.mayStillSend` is where that is decided, once, purely. The snapshot
  // is the one taken before the read; the live side is read here and nowhere
  // else.
  // THE CLIENT THE VERDICT SAW is the one the request goes to. Everything
  // between here and `sendRequest` is synchronous, so the two cannot differ
  // today -- capturing it says so, and keeps saying it if a statement with
  // an await is ever added between them.
  const sentClient = client;
  const verdict = core.mayStillSend(
    attempt,
    core.previewNow(generation, picked, clientEpoch, stopCount, !!sentClient)
  );
  if (!verdict.send) {
    log(`preview: render ${mine} was abandoned while its parameters were read (${verdict.why})`);
    if (mine === generation) renderInFlight = false;
    setPreviewStatus();
    return;
  }

  // Said only now, so nothing ever describes a report the user has left.
  if (prepared.notice) paramsNoticeOnce(sentPick, prepared.notice.reason, prepared.notice.line);
  if (prepared.read) {
    // A file that was read is a file that is there: forget that we once said
    // it was missing, so a LATER deletion is announced again.
    paramsNotices.delete(core.paramsNoticeKey(sentPick, "missing"));
  }
  // U5: one warning per FILE per session, and NEVER a refusal -- a report
  // may legitimately take a `token` parameter, and a block the developer
  // cannot override is a feature that gets turned off.
  const warning = (prepared.warnings || [])[0];
  if (warning && !warnedCredentialFiles.has(prepared.path)) {
    warnedCredentialFiles.add(prepared.path);
    log(`preview: ${prepared.path}: ${warning}`);
    vscode.window.showWarningMessage("Ermine: " + warning);
  }

  if (prepared.refusal) {
    // G7: the render DOES NOT HAPPEN. The tab shows the named refusal
    // through the same path every other failure takes, the status bar goes
    // back to its idle state, and nothing was taken that has to be released
    // -- the wedge latch was never set and no request is out.
    const refusal = core.paramsRefusalAnswer(prepared.refusal, prepared.path, mine);
    log(`preview: render ${mine} REFUSED (${refusal.paramsProblem}): ${refusal.message}`);
    // NOT `lastServerAnswer` (review nit 5): that one is the last answer a
    // SERVER gave, and `shouldRerenderOnFileEvent` reads it to decide
    // whether the picked report is sitting on a placement 404. A params
    // refusal overwriting it would disarm the Q11 watcher and lose the
    // render that brings a deleted report back.
    lastAnswer = refusal;
    if (mine === generation) renderInFlight = false;
    await showAnswer(refusal, reveal === true);
    setPreviewStatus();
    return;
  }

  // WP-22's `params` event, with the params ACTUALLY SENT (after the
  // `$schema` strip), which is why re-formatting a file or changing its
  // `$schema` line keeps the same fingerprint and does not clear the mark.
  applyGuard(core.guardReduce(wedgeMark, { type: "params", pick: sentPick, params: prepared.params }));

  // WP-22's ONE CONSULTATION, REACHED FROM ITS SECOND PLACE (S2 review M6,
  // and the user's own sentence: a report that wedged "and it didn't
  // change" must not be re-rendered without a confirmation).
  //
  // THIS IS THE MOMENT THE EXTENSION KNOWS whether anything changed: the
  // fingerprint has just been computed and handed to the guard. If the mark
  // STILL stands for this pick, then the bytes of the params file moved and
  // the parameters did not -- a re-format, a format-on-save, a touched
  // `$schema` line -- and re-issuing the render that wedged the server is
  // exactly the loop WP-22 exists to close. `shouldAutoRender` is the SAME
  // function `applyStuck` consults; only its trigger vocabulary grew.
  const permitted = core.mayAutoRender(wedgeMark, sentPick, trigger, scheduledAt);
  if (!permitted.render) {
    log(`preview: render ${mine} is HELD (${trigger}: ${permitted.why})`);
    if (mine === generation) renderInFlight = false;
    setPreviewStatus();
    holdRender(trigger);
    return;
  }

  lastParamsSent = prepared.params;
  // M1: the latch the `Stopped` handler reads, cleared only on a settled
  // result below. It carries the params too, so a wedge is marked with what
  // the server was actually given.
  inFlightRender = { generation: mine, pick: sentPick, params: prepared.params };
  log(
    `preview: render ${attempt.label} (generation ${mine}; ${reason}; ` +
      `${prepared.read ? "params from " + prepared.path : "empty parameters"})`
  );

  let answer;
  try {
    // THE REQUEST IS BUILT FROM THE SNAPSHOT, not from the globals (review
    // M2's R9/R10, which swapped each for a live value and survived every
    // test): the uri, the binding, the roots and the generation all come
    // from the one object this render was decided on.
    answer = await sentClient.sendRequest("ermine/render", core.renderRequest(attempt, prepared.params));
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
          // WP-8: and the params THIS render sent, so that editing them
          // clears the mark this rejection is about to set.
          params: prepared.params,
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
  // Review nit 5: the Q11 watcher asks whether the last SERVER answer was a
  // placement 404, and a params refusal is not an answer from any server.
  lastServerAnswer = answer;
  if (core.isPlacement404(answer)) {
    log(`preview: the pick cannot be placed (${answer.reason}); watching ${attempt.pick.fsPath} for it to come back`);
  }
  const stuckEvent = {
    type: "answer",
    stuck: !!(answer && answer.stuck === true),
    message: answer && answer.message,
    seqAtSend: sentAtMark,
  };
  // WP-22, and the same acceptance test the banner uses: a stuck refusal
  // decided BEFORE a clear raises no banner and marks nothing. It is
  // computed ONCE and handed to all three reducers, so they cannot disagree
  // about whether this event happened.
  const answerApplies = core.stuckEventApplies(stuckState, stuckEvent);
  applyGuard(
    core.guardReduce(wedgeMark, {
      type: "answer",
      stuck: stuckEvent.stuck,
      applies: answerApplies,
      // N2: the pick this ANSWER is about, not whatever is current now.
      pick: sentPick,
      // WP-8: and the params THIS render sent, not whatever the next one
      // will. A mark minted here is cleared by changing exactly these.
      params: prepared.params,
      at: Date.now(),
    })
  );
  // WP-22 (c): the wedged ANSWER arrives before the notification (MEASURED
  // over the wire), and the two are ONE incident -- the second of them
  // re-arms nothing, because only the rising edge arms.
  applyRestart(core.restartReduce(restartState, core.restartEvents.answer(stuckEvent.stuck, answerApplies, Date.now())));
  applyStuck(core.stuckReduce(stuckState, stuckEvent), core.TRIGGER_ANSWER);
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
      // WP-8: the module IS the params directory, so a pick that had none
      // had no params path either (`no-module`) and no watcher on one. Both
      // exist from here on, and the next render will find the file.
      forgetParamsNotices();
      installWatcher();
      setPreviewStatus();
      // AND RENDER (S2 review M4). Until the module was known there was no
      // params PATH, so this render went out with `{}` and a params file
      // sitting on disk was ignored -- and nothing else would have
      // scheduled another. It carries NO evidence of change, so it is one
      // of the triggers the consultation can refuse: a report that wedged
      // and has not changed is not re-rendered by learning its name.
      scheduleRender("the module name was learned", core.TRIGGER_MODULE_LEARNED);
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
    if (!watcher) {
      // Not a reason to skip the PARAMS watcher below: the two are
      // independent triggers on two different files.
      installParamsWatcher();
      return;
    }
    const fire = (uri) => {
      if (!picked) return;
      const where = uri && uri.fsPath ? uri.fsPath : picked.fsPath;
      // N1 (WP-22 review): the picked report's OWN file was created or
      // changed. That is the same evidence a save is -- and the watcher
      // fires exactly where `invalidated` cannot, because the module never
      // loaded -- so it clears the mark through the same rule, whether or
      // not it goes on to render.
      applyGuard(core.guardReduce(wedgeMark, { type: "save", path: where }));
      if (core.shouldRerenderOnFileEvent(picked, lastServerAnswer, where)) {
        scheduleRender("the picked report's own file appeared or changed after a placement 404",
                       core.TRIGGER_FILE_EVENT);
      }
    };
    pickWatchers = [watcher, watcher.onDidCreate(fire), watcher.onDidChange(fire)];
  } catch (err) {
    log(`preview: could not watch ${picked.fsPath}: ${err && err.message ? err.message : err}`);
  }
  installParamsWatcher();
}

/**
 * WP-8 S2: a watcher on the PARAMS FILE, for the edits `onDidSaveTextDocument`
 * cannot see -- a `git checkout`, a script, another editor, the file being
 * deleted. It is installed beside the Q11 watcher, disposed with it, and
 * re-created whenever the pick changes or its module name is learned, since
 * the module is the directory the file lives in.
 *
 * THE PATTERN IS RELATIVE TO THE WORKSPACE FOLDER, not to the params
 * DIRECTORY, and that is the whole reason `paramsPaths` answers a
 * `relativeGlob`: `.ermine/preview/<Module>/` does not exist until somebody
 * writes it, and a watcher rooted at a directory that is not there cannot
 * report the file appearing inside it (*external*, and UNVERIFIED here like
 * everything about a real editor).
 *
 * BOTH TRIGGERS GO THROUGH `scheduleRender`, so a save that fires the
 * document event AND the watcher inside the 150 ms window costs ONE render.
 *
 * **LOCAL WORKSPACES ONLY** (S2 review M7), for the same reason as
 * `readParamsFile`: `vscode.Uri.file(folder)` drops the scheme and the
 * authority, so on a remote or virtual workspace this pattern is rooted at a
 * local path that is not there. Stated, not pretended away.
 */
function installParamsWatcher() {
  if (!picked) return;
  const folder = core.paramsFolderFor(picked.fsPath, workspaceFolderPaths());
  const paths = core.paramsPaths(picked, folder);
  if (paths.problem || !folder) return;
  try {
    const pattern = new vscode.RelativePattern(vscode.Uri.file(folder), paths.relativeGlob);
    const watcher = vscode.workspace.createFileSystemWatcher(pattern);
    if (!watcher) return;
    const fire = (what) => () => {
      if (!picked) return;
      scheduleRender(`the params file was ${what} outside the editor`, core.TRIGGER_PARAMS_FILE);
    };
    pickWatchers.push(
      watcher,
      watcher.onDidCreate(fire("created")),
      watcher.onDidChange(fire("changed")),
      // A DELETED params file is not an error: the next render sends `{}`
      // and says so once, which is WP-7's own behaviour for a report that
      // never had one.
      watcher.onDidDelete(fire("deleted"))
    );
    log(`preview: watching ${paths.paramsPath} for parameter changes`);
  } catch (err) {
    log(`preview: could not watch the params file: ${err && err.message ? err.message : err}`);
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

/**
 * TEARDOWN IS A STATE, NOT AN EVENT (S2 review nit 6). `picked` used to be
 * assigned in two places and cleared in none, so `mayStillSend`'s
 * `pick-cleared` arm -- documented as "a teardown" -- was unreachable, and a
 * render sitting in its file read SURVIVED `deactivate()` and went on to
 * send and to touch a status bar item that was being disposed. The new await
 * widened a window that already existed.
 */
let previewDisposed = false;

function disposePreview() {
  previewDisposed = true;
  // The render in its read now sees `pick-cleared` and abandons, which is
  // the case that arm was written for.
  picked = undefined;
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
  heldRefusedToken = undefined;
  inFlightRender = null;
  // WP-22 (c): the grace dies with the window. The reducer is asked rather
  // than the timer merely cleared, so nothing that runs after this can see
  // a state that still thinks a restart is coming. `applyRestart` is NOT
  // used: it would touch a status bar item that is being disposed.
  const stopped = core.restartReduce(restartState, core.restartEvents.deactivate());
  restartState = stopped.state;
  if (stopped.effects.disarm) log("preview: the automatic restart is disarmed (" + stopped.effects.why + ")");
  clearRestartTimer();
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
    // WP-8: a fresh window has sent nothing and said nothing. The restored
    // MARK keeps its own `paramsFingerprint` -- it was written with the
    // params that were in force when the report wedged -- so the first
    // render after a reload compares against that and clears it if the file
    // changed while the window was closed.
    forgetParamsNotices();
    lastParamsSent = undefined;
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
  heldRefusedToken = undefined;
  lastAnswer = undefined;
  lastServerAnswer = undefined;
  // WP-8: another report, another params file. Nothing has been sent for
  // this pick yet, and nothing we said about the last one's file applies.
  forgetParamsNotices();
  lastParamsSent = undefined;
  rememberPick();
  installWatcher();
  setPreviewStatus();
  // The user asked for this one, so it reveals the tab.
  await renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
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
  await renderNow("Ermine: Render Report to JSON", true, core.TRIGGER_EXPLICIT);
}

// ----------------------------------------------------------------- activate

async function activate(context) {
  channel = vscode.window.createOutputChannel("Ermine");
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  status.command = "ermine.showOutput";
  context.subscriptions.push(channel, status);

  context.subscriptions.push(
    vscode.commands.registerCommand("ermine.restartServer", () => restart(context, core.RESTART_BY_USER)),
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
          scheduleRender("ermine.preview.roots changed", core.TRIGGER_ROOTS);
        } catch (err) {
          log(`preview: could not re-resolve the roots: ${err && err.message ? err.message : err}`);
        }
      }
      // WP-22 (c): the grace is read here and nowhere else. A change to 0
      // disarms a grace that is already running; a change to another
      // non-zero value re-arms it at the new value, from now.
      if (event.affectsConfiguration("ermine.preview.restartAfterStuckSeconds")) {
        applyRestart(core.restartReduce(restartState, core.restartEvents.setting(restartGraceValue(), Date.now())));
      }
      // These three only take effect on a fresh process.
      if (
        event.affectsConfiguration("ermine.serverPath") ||
        event.affectsConfiguration("ermine.logFile") ||
        event.affectsConfiguration("ermine.maxHeap")
      ) {
        await restart(context, core.RESTART_BY_USER);
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
      const saved = document && (document.fileName || (document.uri && document.uri.fsPath));
      if (wedgeMark) applyGuard(core.guardReduce(wedgeMark, { type: "save", path: saved }));
      // WP-8 S2, G9: saving THIS pick's params file re-renders it. The
      // decision is `core.shouldRerenderOnParamsSave`'s (a path compare,
      // case-insensitive on win32); the folder is the one that CONTAINS the
      // report, never `folders[0]`.
      //
      // IT IS NOT SUPPRESSED WHILE HELD, and that follows WP-22's own rule
      // rather than bending it: the guard is consulted at exactly ONE site
      // (the restart's automatic re-render), and every other automatic
      // trigger -- `invalidated`, the Q11 watcher, a roots change -- is
      // "self-evidently a change" and is not suppressed either. Editing a
      // params file is the developer doing something. If what they did
      // changed the parameters, the render's own `params` event CLEARS the
      // mark on the way out; if it did not (a re-format), the mark stands
      // and the status bar still says `held` while the render runs.
      if (!picked || !saved) return;
      const folder = core.paramsFolderFor(picked.fsPath, workspaceFolderPaths());
      if (core.shouldRerenderOnParamsSave(picked, saved, folder)) {
        scheduleRender("the params file was saved", core.TRIGGER_PARAMS_FILE);
      }
    })
  );

  // WP-22 (c): the grace, read once at activation. DEFAULT 0 = never, so
  // by default this whole feature does nothing at all.
  restartState = core.initialRestartState(restartGraceValue());

  restorePick(context);

  // Not awaited on purpose — activation must not wait on the server. It
  // takes an epoch like every other start (M2), so a restart during the
  // first run's classpath warm-up supersedes it instead of racing it.
  startEpoch += 1;
  startClient(context, startEpoch);
}

function deactivate() {
  disposePreview();
  return stopQuietly(client);
}

module.exports = { activate, deactivate };
