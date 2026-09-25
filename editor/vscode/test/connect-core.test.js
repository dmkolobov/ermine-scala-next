"use strict";

// WP-13, the extension half: database profiles and the prompted password.
//
//     cd editor/vscode && node --test test/connect-core.test.js
//     (and `npm run test:preview`, which runs this file after preview-core's)
//
// A SEPARATE FILE ONLY BECAUSE TWO ROLES EDITED test/preview-core.test.js IN
// THE SAME NIGHT; ITS HEADER RULES APPLY HERE UNCHANGED, and the one that
// matters most is restated:
//
//     A MODEL MUST MUTATE, OMIT AND CAPTURE EXACTLY WHAT THE GLUE MUTATES,
//     OMITS AND CAPTURES.
//
// So `glueModel` below builds every reducer event through
// `core.connectEvents.*` (the glue's own builders), keys its Map with
// `core.profileKey`, builds the request with `core.connectRequest`, applies
// the effects in `applyConnect`'s order, and the "glue pins" at the bottom
// read src/extension.js and fail if any of that stops being true there.
//
// Each REVERSE MUTANT the brief names is run against the same scenario as the
// real code and must be CAUGHT, by name:
//   "password logged"              a log line that carries the typed password
//   "held across a url change"     a Map key without the URL
//   "reconnect re-rendering twice" the restart's re-render not deferred
//   "auth failure keeping the entry" `forget` dropped for class auth

const { test } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const core = require("../src/preview-core");

const PASSWORD = "Tr0ub4dor.and_3-ish";
const MSSQL_URL = "jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true";
const MSSQL = { id: "sales-mssql", dialect: "mssql", url: MSSQL_URL, user: "ermine" };
const SQLITE = { id: "sales-sqlite", dialect: "sqlite", url: "jdbc:sqlite:/home/u/data/out/sales/xs/sales.sqlite" };
const PICK = core.makePick("file:///w/doc/DbFetchTopN.e", "/w/doc/DbFetchTopN.e", "report", "DbFetchTopN", ["/w/doc"]);

// ------------------------------------------------------ the validation table

test("profiles: the validation table", () => {
  const rows = [
    // [what, profiles, active, expect: {active id | null}, problem regex | null]
    ["the playtest profile", [MSSQL], "sales-mssql", "sales-mssql", null],
    ["no active id is the in-memory local", [MSSQL], "", null, null],
    ["`local` with no such profile is the built-in", [MSSQL], "local", null, null],
    ["an unknown id", [MSSQL], "sales", null, /no profile has that id \(there are: sales-mssql\)/],
    ["a dialect outside the vocabulary", [{ ...MSSQL, dialect: "oracle" }], "sales-mssql", null, /dialect oracle; one of sqlite, mssql/],
    ["dialect is case-insensitive", [{ ...MSSQL, dialect: "MSSQL" }], "sales-mssql", "sales-mssql", null],
    ["duplicate ids refuse both", [MSSQL, { ...MSSQL, url: "jdbc:sqlserver://10.0.0.9" }], "sales-mssql", null,
      /defined 2 times; ids must be unique/],
    ["password= in the url", [{ ...MSSQL, url: MSSQL_URL + ";password=" + PASSWORD }], "sales-mssql", null, /url carries credentials/],
    ["user= in the url", [{ ...MSSQL, url: MSSQL_URL + ";user=ermine" }], "sales-mssql", null, /url carries credentials/],
    ["pwd= after a ?", [{ ...MSSQL, url: "jdbc:mysql://h/db?pwd=" + PASSWORD }], "sales-mssql", null, /url carries credentials/],
    ["user:pass@host", [{ ...MSSQL, dialect: "mysql", url: "jdbc:mysql://ermine:" + PASSWORD + "@h/db" }], "sales-mssql", null,
      /url carries credentials/],
    ["a password key in the profile", [{ ...MSSQL, password: PASSWORD }], "sales-mssql", null, /a password never goes in settings/],
    ["a relative sqlite path (Q-S5 b)", [{ ...SQLITE, url: "jdbc:sqlite:data/sales.sqlite" }], "sales-sqlite", null, /not absolute/],
    ["an absolute sqlite path", [SQLITE], "sales-sqlite", "sales-sqlite", null],
    ["a windows sqlite path", [{ ...SQLITE, url: "jdbc:sqlite:C:\\data\\sales.sqlite" }], "sales-sqlite", "sales-sqlite", null],
    ["the in-memory sqlite url", [{ ...SQLITE, url: "jdbc:sqlite::memory:" }], "sales-sqlite", "sales-sqlite", null],
    ["not a jdbc url", [{ ...MSSQL, url: "sqlserver://h" }], "sales-mssql", null, /no jdbc: url/],
    ["a scanner outside the vocabulary", [{ ...MSSQL, scanner: "fast" }], "sales-mssql", null, /scanner fast; one of default, noTransactions/],
    ["noTransactions is passed on (the server decides the dialect)", [{ ...MSSQL, scanner: "noTransactions" }], "sales-mssql", "sales-mssql", null],
    ["a profile with no id", [{ dialect: "mssql", url: MSSQL_URL }], "x", null, /no id/],
  ];
  for (const [what, profiles, active, want, problem] of rows) {
    const c = core.profilesCheck(profiles, active);
    assert.strictEqual(c.active ? c.active.id : null, want, what);
    const all = c.problems.concat(c.activeProblem ? [c.activeProblem] : []).join(" | ");
    if (problem) assert.match(all, problem, what);
    else assert.strictEqual(all, "", what + ": " + all);
    // A REFUSAL NEVER ECHOES THE URL OR THE PASSWORD (it may hold one).
    assert.ok(!all.includes(PASSWORD), what + ": the password leaked into a problem");
    for (const p of profiles) {
      if (p && typeof p.url === "string") assert.ok(!all.includes(p.url), what + ": a url leaked into a problem");
    }
  }
  assert.match(core.profilesCheck("nope", "").problems[0], /not a list/);
  assert.match(core.profilesCheck([], 7).activeProblem, /not a profile id/);
});

test("profiles: the key is a digest of id, url and user, and moves with each", () => {
  const k = core.profileKey(MSSQL);
  assert.match(k, /^profile:[0-9a-f]{64}$/);
  assert.ok(!k.includes("127.0.0.1"), "the key never holds the url in clear");
  assert.notStrictEqual(core.profileKey({ ...MSSQL, url: MSSQL_URL.replace("1433", "1434") }), k, "url");
  assert.notStrictEqual(core.profileKey({ ...MSSQL, user: "sa" }), k, "user");
  assert.notStrictEqual(core.profileKey({ ...MSSQL, id: "other" }), k, "id");
  assert.strictEqual(core.profileKey({ ...MSSQL, dialect: "sqlserver" }), k, "the dialect is not part of the secret's identity");
  assert.strictEqual(core.profileKey(null), null);
  assert.deepStrictEqual(core.heldKeysToForget([k, "profile:gone"], [MSSQL]), ["profile:gone"]);
});

test("profiles: the prompt names user @ host and the id, and fixes password + ignoreFocusOut", () => {
  const p = core.passwordPrompt(MSSQL);
  assert.strictEqual(p.password, true);
  assert.strictEqual(p.ignoreFocusOut, true);
  assert.match(p.prompt, /ermine @ 127\.0\.0\.1 \(profile sales-mssql\)/);
  assert.ok(!p.prompt.includes("databaseName"), "the prompt names the host, not the url");
  assert.strictEqual(core.profileHost("jdbc:sqlserver://[::1]:1433;x=y"), "[::1]");
  assert.strictEqual(core.profileHost(SQLITE.url), "sales.sqlite");
});

test("profiles: connectRequest is the only builder with the password, and only for a user", () => {
  assert.deepStrictEqual(core.connectRequest(MSSQL, PASSWORD),
    { profile: { id: "sales-mssql", dialect: "mssql", url: MSSQL_URL, user: "ermine" }, password: PASSWORD });
  assert.deepStrictEqual(core.connectRequest(SQLITE, PASSWORD),
    { profile: { id: "sales-sqlite", dialect: "sqlite", url: SQLITE.url } }, "no user, no password on the wire");
  assert.deepStrictEqual(core.connectRequest(MSSQL, undefined).password, undefined);
});

// ------------------------------------------------------------- the model

/**
 * THE GLUE'S CONNECT PATH, statement for statement (src/extension.js
 * `connect`, `applyConnect`, `askPassword`, `sendConnect`, `sendDisconnect`,
 * `showConnectFailure`, `rerenderAfterConnect`, `connectCommand`,
 * `disconnectCommand`, `onProfileSettingsChanged`, and the three hooks in
 * `onClientStopped`, the `Running` edge and `applyStuck`). Async edges are
 * explicit: a prompt waits for `type(i, text)`, a request for `answer(i, a)`.
 *
 * Mutant switches: `keyFn` replaces `core.profileKey`; `reduce` replaces
 * `core.connectReduce`; `noDefer` skips the Running edge's deferral;
 * `logSecret` logs the typed password.
 */
function glueModel(opts) {
  const o = opts || {};
  const keyOf = o.keyFn || core.profileKey;
  const reduce = o.reduce || core.connectReduce;
  const m = {
    held: new Map(),
    state: core.initialConnectState(),
    running: false,
    client: true,
    generation: 0,
    picked: PICK,
    mark: null,
    settings: { profiles: [MSSQL, SQLITE], profile: "sales-mssql", trace: "off" },
    prompts: [], sent: [], disconnects: 0, logs: [], errors: [], scheduled: [], heldQuestions: [],
    panel: [], stuckRunning: true, connectRerenders: 0, workspace: {},
    timer: null, clock: 0, renders503: [], notified: 0,
  };
  const log = (line) => m.logs.push(line);
  // the glue reads `inspect(...)`, and only `globalValue` counts (A2); the
  // model's `settings` is the USER scope, `workspace` the workspace scope
  const insp = (key) => {
    const i = { globalValue: m.settings[key] };
    if (m.workspace[key] !== undefined) i.workspaceValue = m.workspace[key];
    return i;
  };
  m.check = () => (o.checkFn || core.userScopeProfilesCheck)(insp("profiles"), insp("profile"));
  m.connect = (cause) => {
    const check = m.check();
    if (!m.client || !m.running) { log("db: not connecting yet (" + cause + ")"); return; }
    const key = core.profileKey(check.active) === null ? null : keyOf(check.active);
    m.apply(reduce(m.state, core.connectEvents.request(cause, check, m.settings.trace,
                                                       key !== null && m.held.has(key), m.generation > 0)),
            check.active);
  };
  m.apply = (result, profile) => {
    const before = m.state;
    m.state = result.state;
    const fx = result.effects;
    if (fx.line) log(fx.line);
    if (fx.forget && before.key) {
      // the glue deletes `before.key`; the model's Map is keyed by `keyOf`,
      // which is `core.profileKey` unless a mutant replaced it
      for (const k of Array.from(m.held.keys())) if (k === before.key || (o.keyFn && profile && k === keyOf(profile))) m.held.delete(k);
    }
    if (fx.sendDisconnect && m.client && m.running) m.disconnects += 1;
    if (fx.prompt !== null && profile) m.prompts.push({ serial: fx.prompt, profile, text: core.passwordPrompt(profile) });
    if (fx.send !== null && profile) {
      m.sent.push({ serial: fx.send, profile, body: core.connectRequest(profile, m.held.get(keyOf(profile))) });
    }
    if (fx.failed) {
      if (m.picked && m.generation > 0) m.panel.push(core.connectFailureAnswer(m.state, m.generation));
      if (fx.notify) m.errors.push({ text: core.connectFailureText(m.state), retry: fx.offerRetry });
    }
    // the ONE backoff timer, on the model's fake clock
    if (fx.retryIn !== null) m.timer = { at: m.clock + fx.retryIn, token: fx.retryToken };
    if (!m.state.retry || o.noCancel) { if (!o.noCancel) m.timer = null; }
    if (fx.reconnect) m.connect(fx.reconnect);
    if (fx.rerender) { m.connectRerenders += 1; m.rerenderAfterConnect(fx.rerender); }
    m.status = core.connectStatusBar(m.state);
    return fx;
  };
  m.type = (i, text) => {
    const p = m.prompts[i];
    let secret = text;
    const entered = typeof secret === "string" && secret.length > 0;
    if (entered && p.serial === m.state.serial && m.state.phase === "prompting") m.held.set(keyOf(p.profile), secret);
    if (o.logSecret && entered) log("db: typed " + secret);
    secret = undefined;
    m.apply(reduce(m.state, core.connectEvents.prompted(p.serial, entered)), p.profile);
  };
  // `canReconnectNow(profile)`: no user, or a password held for its key
  m.canReconnect = (p) => {
    const active = p || m.check().active;
    return !!active && (!active.user || m.held.has(keyOf(active)));
  };
  m.answer = (i, answer) => {
    const s = m.sent[i];
    m.apply(reduce(m.state, core.connectEvents.answer(s.serial, answer, m.canReconnect(s.profile))), s.profile);
  };
  m.reject = (i, err) => {
    const s = m.sent[i];
    m.apply(reduce(m.state, core.connectEvents.rejected(s.serial, err, m.canReconnect(s.profile))), s.profile);
  };
  // advance the fake clock; the timer fires if due (`armReconnectTimer`)
  m.tick = (ms) => {
    m.clock += ms;
    if (m.timer && m.timer.at <= m.clock) {
      const token = m.timer.token;
      m.timer = null;
      m.apply(reduce(m.state, core.connectEvents.retryDue(token)));
    }
  };
  // renderNow's NEW-2 arm: a 503 not-connected first tries ONE connect
  m.render503 = () => {
    m.generation += 1;
    const may = o.renderAlways ? true : core.renderMayConnect(m.state, m.canReconnect());
    if (may) { m.renders503.push("connect"); m.connect("render"); return; }
    m.renders503.push("banner");
  };
  m.rerenderAfterConnect = (trigger) => {
    if (!m.picked) return;
    const permitted = core.mayAutoRender(m.mark, m.picked, trigger);
    if (permitted.render) m.scheduled.push(trigger);
    else m.heldQuestions.push(trigger);
  };
  // the `Running` edge: connect FIRST, then `applyStuck`'s re-render (only
  // after a stop, as `stuckReduce`'s `rerender: !s.running`)
  m.runningEdge = () => {
    const afterStop = !m.stuckRunning;
    m.stuckRunning = true;
    m.running = true;
    m.connect("running");
    if (!afterStop) return;
    const trigger = core.TRIGGER_RESTART;
    const deferred = !o.noDefer &&
      m.apply(reduce(m.state, core.connectEvents.deferRender(trigger))).deferred;
    if (!deferred) m.rerenderAfterConnect(trigger);
  };
  m.stopped = () => {
    m.running = false;
    m.stuckRunning = false;
    m.apply(reduce(m.state, core.connectEvents.stopped()));
  };
  m.serverDisconnected = (reason) => m.apply(reduce(m.state, core.connectEvents.disconnected(reason)));
  m.connectCommand = () => { if (m.check().active) m.connect("command"); };
  m.disconnectCommand = () => m.apply(reduce(m.state, core.connectEvents.disconnectCommand()));
  m.retry = () => m.connect("retry");
  m.settingsChanged = () => {
    const check = m.check();
    // the glue calls `core.heldKeysToForget`, which keys with `core.profileKey`;
    // a key mutant replaces that function everywhere, so here too
    const forget = o.keyFn
      ? Array.from(m.held.keys()).filter((k) => !check.profiles.map(keyOf).includes(k))
      : core.heldKeysToForget(m.held.keys(), check.profiles);
    for (const k of forget) m.held.delete(k);
    if (core.connectSettingsMoved(m.state, check, m.settings.trace)) m.connect("profile");
    else m.status = core.connectStatusBar(m.state);
  };
  // everything the user or a log can see, for the leak checks
  m.visible = () => [].concat(
    m.logs, m.errors.map((e) => e.text), m.prompts.map((p) => p.text.prompt + " " + p.text.title),
    m.panel.map((a) => JSON.stringify(a)), m.status ? [m.status.text || "", m.status.tooltip || ""] : [],
    [JSON.stringify(m.state)]);
  return m;
}

const OK = { ok: true, host: "127.0.0.1", database: "ErmineSales", server: "16.0.4295.3" };
const AUTH = { ok: false, class: "auth", kept: false, message: "SQLServerException: login failed for <user> @ <host>" };

/** The morning: activation (the first Running), one prompt, one connect, connected. */
function connected(opts) {
  const m = glueModel(opts);
  m.runningEdge();
  assert.strictEqual(m.prompts.length, 1, "the first Running prompts");
  m.type(0, PASSWORD);
  assert.strictEqual(m.sent.length, 1);
  m.answer(0, OK);
  return m;
}

test("connect: activation prompts once, sends the password on the connect only, and holds it", () => {
  const m = connected();
  assert.strictEqual(m.state.phase, "connected");
  assert.strictEqual(m.sent[0].body.password, PASSWORD);
  assert.deepStrictEqual(m.sent[0].body.profile, { id: "sales-mssql", dialect: "mssql", url: MSSQL_URL, user: "ermine" });
  assert.strictEqual(m.held.get(core.profileKey(MSSQL)), PASSWORD);
  assert.strictEqual(m.status.text, "$(database) sales-mssql (mssql) @ 127.0.0.1");
  assert.match(m.status.tooltip, /database: ErmineSales/);
  // HELD: the Connect command reconnects without a prompt
  m.connectCommand();
  assert.strictEqual(m.prompts.length, 1, "prompt-or-held: held, so no second prompt");
  assert.strictEqual(m.sent[1].body.password, PASSWORD);
  assert.deepStrictEqual(m.scheduled, [], "no render has been sent yet, so there is none to re-send");
  for (const text of m.visible()) {
    assert.ok(!text.includes(PASSWORD), "the password is visible: " + text);
    assert.ok(!text.includes("databaseName="), "the url is visible: " + text);
  }
});

test("connect: a profile with no user never prompts and never sends a password", () => {
  const m = glueModel();
  m.settings.profile = "sales-sqlite";
  m.runningEdge();
  assert.strictEqual(m.prompts.length, 0);
  assert.strictEqual(m.sent.length, 1);
  assert.strictEqual("password" in m.sent[0].body, false);
  m.answer(0, { ok: true, host: "sales.sqlite" });
  assert.strictEqual(m.status.text, "$(database) sales-sqlite (sqlite) @ sales.sqlite");
});

test("connect: no profile, no request, no status bar item", () => {
  const m = glueModel();
  m.settings.profile = "";
  m.runningEdge();
  assert.deepStrictEqual([m.prompts.length, m.sent.length, m.disconnects], [0, 0, 0]);
  assert.deepStrictEqual(core.connectStatusBar(m.state), { hidden: true });
});

test("connect: an authentication failure FORGETS the password and offers Retry / Disconnect", () => {
  const m = connected();
  m.generation = 3;                                   // a render has been sent
  m.connectCommand();
  m.answer(1, AUTH);
  assert.strictEqual(m.held.size, 0, "auth failure forgets");
  assert.strictEqual(m.errors.length, 1);
  assert.strictEqual(m.errors[0].retry, true);
  assert.strictEqual(m.status.text, "$(database) sales-mssql: auth");
  assert.strictEqual(m.panel[0].status, 503);
  assert.strictEqual(m.panel[0].reason, "connect-auth");
  assert.strictEqual(m.panel[0].generation, 3);
  // A8: no unattended retry -- a restart's Running edge does not prompt
  m.stopped();
  m.runningEdge();
  assert.strictEqual(m.prompts.length, 1, "no unattended prompt after a rejected login");
  // Retry is explicit and prompts
  m.retry();
  assert.strictEqual(m.prompts.length, 2);
  // even `kept: true` (locked / expired) forgets: the brief's rule is per class
  const k = connected();
  k.connectCommand();
  k.answer(1, { ...AUTH, kept: true });
  assert.strictEqual(k.held.size, 0);
});

test("connect: kept:false forgets for ANY class; driver / unreachable / profile keep it", () => {
  for (const [cls, kept, forgets, reason] of [
    ["connect", false, true, "connect-unreachable"], ["connect", true, false, "connect-unreachable"],
    ["unreachable", true, false, "connect-unreachable"], ["unreachable", false, true, "connect-unreachable"],
    ["driver", true, false, "connect-driver"], ["profile", true, false, "connect-profile"],
  ]) {
    const m = connected();
    m.connectCommand();
    m.answer(1, { ok: false, class: cls, kept, message: "x" });
    assert.strictEqual(m.held.size === 0, forgets, cls + "/" + kept);
    assert.strictEqual(m.errors[0].retry, false, cls + ": only auth offers Retry");
    assert.strictEqual(m.state.reason, reason, cls);
    // NEW-2: a retriable class with the password kept goes into the backoff
    const retries = !forgets && cls !== "profile";
    assert.strictEqual(m.status.text, retries ? "$(sync) sales-mssql: reconnecting (2/3)" : "$(database) sales-mssql: " + cls,
                       cls + "/" + kept);
  }
  // a server that sends its own Q-S4 reason is believed
  const m = connected();
  m.connectCommand();
  m.answer(1, { ok: false, class: "unreachable", kept: true, reason: "connect-unreachable", message: "refused" });
  assert.strictEqual(m.state.reason, "connect-unreachable");
  assert.strictEqual(m.status.text, "$(sync) sales-mssql: reconnecting (2/3)");
  // a class nobody declared is read as unreachable, never as auth
  const odd = connected();
  odd.connectCommand();
  odd.answer(1, { ok: false, class: "weird", message: "x" });
  assert.deepStrictEqual([odd.state.cls, odd.held.size], ["unreachable", 1]);
  // an older server with no connect method is a named failure, entry kept
  const old = glueModel();
  old.runningEdge();
  old.type(0, PASSWORD);
  old.reject(0, { code: -32601, message: "Unhandled method ermine/preview/connect" });
  assert.match(old.state.message, /older than the extension/);
  assert.strictEqual(old.held.size, 1);
});

test("connect: disconnected -> automatic reconnect with the HELD password -> the last render re-sent ONCE", () => {
  const m = connected();
  m.generation = 5;
  m.serverDisconnected("recycled after 500 renders");
  assert.strictEqual(m.prompts.length, 1, "reconnecting never prompts");
  assert.strictEqual(m.sent.length, 2);
  assert.strictEqual(m.sent[1].body.password, PASSWORD);
  m.answer(1, OK);
  assert.deepStrictEqual(m.scheduled, [core.TRIGGER_RECONNECTED], "exactly one re-render");
  m.answer(1, OK);                                   // a duplicate or late answer
  assert.deepStrictEqual(m.scheduled, [core.TRIGGER_RECONNECTED], "a second answer re-renders nothing");
  // no password held (e.g. after a rejected login): the reconnect does not ask
  const n = connected();
  n.held.clear();
  n.serverDisconnected("x");
  assert.deepStrictEqual([n.prompts.length, n.sent.length], [1, 1]);
  assert.strictEqual(n.state.phase, "disconnected");
  assert.strictEqual(n.status.text, "$(database) sales-mssql: disconnected");
});

test("connect: a restart reconnects and its re-render is DEFERRED to the answer, one render under `restart`", () => {
  const m = connected();
  m.generation = 2;
  m.stopped();
  m.runningEdge();
  assert.strictEqual(m.prompts.length, 1, "held: the restart does not prompt");
  assert.deepStrictEqual(m.scheduled, [], "nothing goes out before the connect answers");
  m.answer(1, OK);
  assert.deepStrictEqual(m.scheduled, [core.TRIGGER_RESTART], "one render, under WP-22's restart trigger");
  // AND WP-22's RULE HOLDS: a marked pick is HELD, not re-rendered
  const w = connected();
  w.generation = 2;
  w.mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: PICK, params: {}, at: 1 }).mark;
  w.stopped();
  w.runningEdge();
  w.answer(1, OK);
  assert.deepStrictEqual(w.scheduled, []);
  assert.deepStrictEqual(w.heldQuestions, [core.TRIGGER_RESTART]);
  // and the connect itself consulted and cleared nothing
  assert.ok(core.markMatches(w.mark, PICK));
  // with NO profile the restart re-render goes out at once, exactly as before WP-13
  const plain = glueModel();
  plain.settings.profile = "";
  plain.runningEdge();
  plain.stopped();
  plain.runningEdge();
  assert.deepStrictEqual(plain.scheduled, [core.TRIGGER_RESTART]);
});

test("connect: a profile change re-prompts; the old password is never sent to the new url", () => {
  const m = connected();
  m.settings.profiles = [{ ...MSSQL, url: "jdbc:sqlserver://10.9.8.7:1433;databaseName=ErmineSales" }, SQLITE];
  m.settingsChanged();
  assert.strictEqual(m.prompts.length, 2, "a changed url is a new key: prompt again");
  assert.match(m.prompts[1].text.prompt, /ermine @ 10\.9\.8\.7/);
  assert.strictEqual(m.sent.length, 1, "nothing sent before the new password is typed");
  assert.strictEqual(m.held.size, 0, "the old url's password is forgotten: no profile has that key any more");
  // an edit to an INACTIVE profile does nothing
  const n = connected();
  n.settings.profiles = [MSSQL, { ...SQLITE, url: "jdbc:sqlite:/other.sqlite" }];
  n.settingsChanged();
  assert.deepStrictEqual([n.prompts.length, n.sent.length, n.state.phase], [1, 1, "connected"]);
  // switching to no profile disconnects and keeps the (still configured) password
  n.settings.profile = "";
  n.settingsChanged();
  assert.strictEqual(n.disconnects, 1);
  assert.strictEqual(n.held.size, 1);
  assert.deepStrictEqual(n.status, { hidden: true });
  // a prompt overtaken by a profile change stores NOTHING
  const s = glueModel();
  s.runningEdge();
  s.settings.profiles = [{ ...MSSQL, url: "jdbc:sqlserver://10.9.8.7" }];
  s.settingsChanged();
  s.type(0, PASSWORD);                               // the FIRST box, now stale
  assert.strictEqual(s.held.size, 0);
  assert.strictEqual(s.sent.length, 0);
});

test("connect: trace verbose refuses (A7) on every path, and lowering it connects", () => {
  const m = glueModel();
  m.settings.trace = "verbose";
  m.runningEdge();
  m.connectCommand();
  assert.deepStrictEqual([m.prompts.length, m.sent.length], [0, 0]);
  assert.strictEqual(m.status.text, "$(database) sales-mssql: trace is verbose");
  assert.ok(m.logs.some((l) => /verbose/.test(l) && /NOT connecting/.test(l)));
  // the unattended path too: held password, disconnected -> still refused
  const d = connected();
  d.settings.trace = "verbose";
  d.serverDisconnected("x");
  assert.strictEqual(d.sent.length, 1, "the automatic reconnect is refused while verbose");
  m.settings.trace = "messages";
  m.settingsChanged();
  assert.strictEqual(m.prompts.length, 1);
});

test("connect: Disconnect forgets and tells the server; nothing asks again until Connect", () => {
  const m = connected();
  m.disconnectCommand();
  assert.strictEqual(m.held.size, 0);
  assert.strictEqual(m.disconnects, 1);
  assert.strictEqual(m.status.text, "$(database) sales-mssql: not connected");
  m.stopped();
  m.runningEdge();
  assert.strictEqual(m.prompts.length, 1, "a restart after Disconnect does not prompt");
  m.connectCommand();
  assert.strictEqual(m.prompts.length, 2);
  // a cancelled prompt is the same "no"
  const c = glueModel();
  c.runningEdge();
  c.type(0, undefined);
  assert.strictEqual(c.state.phase, "declined");
  c.stopped();
  c.runningEdge();
  assert.strictEqual(c.prompts.length, 1);
});

test("connect: the 503 not-connected is dressed for the panel; other answers pass by identity", () => {
  const s = core.connectReduce(undefined, core.connectEvents.request("command", core.profilesCheck([MSSQL], "sales-mssql"), "off", false, false)).state;
  const a = { ok: false, status: 503, message: "not connected", generation: 4 };
  const d = core.dressNotConnected(a, s);
  assert.strictEqual(d.reason, "not-connected");
  assert.match(d.message, /Ermine: Connect Database/);
  assert.strictEqual(d.generation, 4);
  const other = { ok: false, status: 500, message: "boom" };
  assert.strictEqual(core.dressNotConnected(other, s), other);
  const ok = { ok: true, document: {} };
  assert.strictEqual(core.dressNotConnected(ok, s), ok);
  assert.strictEqual(core.isNotConnected({ ok: false, status: 503, reason: "not-connected", message: "" }), true);
});

test("connect PROPERTY: over random event sequences, no password or url is ever visible and one ok re-renders at most once", () => {
  let seed = 7;
  const rnd = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
  for (let run = 0; run < 400; run++) {
    const m = glueModel();
    m.generation = rnd(2);
    let oks = 0;
    for (let step = 0; step < 20; step++) {
      const pick = rnd(10);
      if (pick === 0) m.runningEdge();
      else if (pick === 1) m.stopped();
      else if (pick === 2 && m.prompts.length) m.type(m.prompts.length - 1, rnd(3) ? PASSWORD : undefined);
      else if (pick === 3 && m.sent.length) { m.answer(m.sent.length - 1, OK); oks++; }
      else if (pick === 4 && m.sent.length) m.answer(m.sent.length - 1, AUTH);
      else if (pick === 5) m.serverDisconnected("r");
      else if (pick === 6) m.connectCommand();
      else if (pick === 7) m.disconnectCommand();
      else if (pick === 8) { m.settings.profile = ["sales-mssql", "sales-sqlite", ""][rnd(3)]; m.settingsChanged(); }
      else m.settings.trace = ["off", "messages", "verbose"][rnd(3)];
    }
    assert.ok(m.connectRerenders <= oks, "more connect re-renders than successful connects");
    for (const text of m.visible()) {
      assert.ok(!text.includes(PASSWORD), "run " + run + ": the password is visible: " + text);
      assert.ok(!text.includes(MSSQL_URL), "run " + run + ": the url is visible: " + text);
    }
    for (const s of m.sent) {
      if (s.body.password !== undefined) {
        assert.strictEqual(s.profile.user, "ermine", "a password only ever goes with a user");
        assert.ok(m.prompts.some((p) => core.profileKey(p.profile) === core.profileKey(s.profile)),
                  "a password only ever goes to the (id, url, user) it was typed for");
      }
    }
  }
});

// ------------------------------------------------------- reverse mutants

test("MUTANT 'held across a url change' is killed", () => {
  // the real code: prompt again (asserted above); the mutant keys by id only
  const mut = connected({ keyFn: (p) => (p ? "id:" + p.id : null) });
  mut.settings.profiles = [{ ...MSSQL, url: "jdbc:sqlserver://10.9.8.7:1433" }];
  mut.settingsChanged();
  const leaked = mut.prompts.length === 1 && mut.sent.length === 2 && mut.sent[1].body.password === PASSWORD &&
                 /10\.9\.8\.7/.test(mut.sent[1].profile.url);
  assert.ok(leaked, "the mutant must send the old password to the new host, or this test proves nothing");
  const real = connected();
  real.settings.profiles = [{ ...MSSQL, url: "jdbc:sqlserver://10.9.8.7:1433" }];
  real.settingsChanged();
  assert.strictEqual(real.sent.length, 1, "killed: the real code does not");
});

test("MUTANT 'reconnect re-rendering twice' is killed", () => {
  const run = (opts) => {
    const m = connected(opts);
    m.generation = 2;
    m.stopped();
    m.runningEdge();
    m.answer(1, OK);
    return m.scheduled.length;
  };
  assert.strictEqual(run({ noDefer: true }), 2, "the mutant (no deferral) must render twice");
  assert.strictEqual(run({}), 1, "killed: the real code renders once");
  // and the reducer-side variant: pending not cleared on ok
  const sticky = (s, e) => {
    const r = core.connectReduce(s, e);
    if (e.type === "answer" && r.effects.rerender) r.state = Object.assign({}, r.state, { pendingRerender: r.effects.rerender, phase: "connecting" });
    return r;
  };
  const m = connected({ reduce: sticky });
  m.generation = 2;
  m.serverDisconnected("x");
  m.answer(1, OK);
  m.answer(1, OK);
  assert.strictEqual(m.scheduled.length, 2, "the sticky mutant re-renders on the duplicate answer");
});

test("MUTANT 'auth failure keeping the entry' is killed", () => {
  const keep = (s, e) => {
    const r = core.connectReduce(s, e);
    if (r.state.cls === "auth") r.effects = Object.assign({}, r.effects, { forget: false });
    return r;
  };
  const mut = connected({ reduce: keep });
  mut.connectCommand();
  mut.answer(1, AUTH);
  mut.retry();
  assert.strictEqual(mut.prompts.length, 1, "the mutant retries the rejected password without asking");
  const real = connected();
  real.connectCommand();
  real.answer(1, AUTH);
  real.retry();
  assert.strictEqual(real.prompts.length, 2, "killed: the real code asks again");
});

test("MUTANT 'password logged' is killed, in the model and in the source pin", () => {
  const mut = glueModel({ logSecret: true });
  mut.runningEdge();
  mut.type(0, PASSWORD);
  assert.ok(mut.visible().some((t) => t.includes(PASSWORD)), "the model sees the mutant's leak");
  const raw = fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const mutated = raw.replace("  secret = undefined;\n  applyConnect(", '  log("db: typed " + secret);\n  secret = undefined;\n  applyConnect(');
  assert.notStrictEqual(mutated, raw, "the mutation must apply");
  assert.ok(passwordPins(mutated).some((v) => /secret/.test(v)), "the pin must catch it: " + passwordPins(mutated).join("; "));
  const viaPost = raw.replace("  secret = undefined;\n  applyConnect(", "  postSnapshot(secret);\n  secret = undefined;\n  applyConnect(");
  assert.ok(passwordPins(viaPost).length > 0, "a postMessage path is caught too");
  const viaGet = raw.replace('log("db: the server let the connection go")',
                             'log("db: " + heldPasswords.get(connState.key))');
  assert.ok(passwordPins(viaGet).length > 0, "a second read of the Map is caught");
  assert.deepStrictEqual(passwordPins(raw), [], "and the real source passes");
});

// ------------------------------------------------------------ glue pins

const REGEX_MAY_START = /[=(,:[!&|?{};+\-*%~^<>]/;
/** test/preview-core.test.js's `codeOf`, copied: comments out, strings and regexes kept. */
function codeOf(text) {
  const s = String(text);
  let out = "";
  let prev = "";
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    const d = s[i + 1];
    if (c === "/" && d === "/") { while (i < s.length && s[i] !== "\n") i++; continue; }
    if (c === "/" && d === "*") { i += 2; while (i < s.length && !(s[i] === "*" && s[i + 1] === "/")) i++; i += 2; continue; }
    if (c === '"' || c === "'" || c === "`") {
      out += c; i += 1;
      while (i < s.length) {
        if (s[i] === "\\") { out += s.slice(i, i + 2); i += 2; continue; }
        out += s[i]; i += 1;
        if (s[i - 1] === c) break;
      }
      prev = c; continue;
    }
    if (c === "/" && REGEX_MAY_START.test(prev)) {
      out += c; i += 1;
      let inClass = false;
      while (i < s.length) {
        if (s[i] === "\\") { out += s.slice(i, i + 2); i += 2; continue; }
        if (s[i] === "[") inClass = true; else if (s[i] === "]") inClass = false;
        out += s[i]; i += 1;
        if (s[i - 1] === "/" && !inClass) break;
      }
      prev = "/"; continue;
    }
    out += c;
    if (!/\s/.test(c)) prev = c;
    i += 1;
  }
  return out;
}

/**
 * THE PASSWORD PINS, as a function so the mutants above can be run through
 * it. Returns the violations (empty = clean). The typed value is the local
 * `secret` in `askPassword`; the held value is only reachable through
 * `heldPasswords`.
 */
function passwordPins(raw) {
  const src = codeOf(raw);
  const v = [];
  const lines = src.split("\n");
  const allowedSecret = [
    /^\s*let secret;$/,
    /^\s*secret = await vscode\.window\.showInputBox\(core\.passwordPrompt\(profile\)\);$/,
    /^\s*secret = undefined;$/,
    /^\s*const entered = typeof secret === "string" && secret\.length > 0;$/,
    /^\s*heldPasswords\.set\(core\.profileKey\(profile\), secret\);$/,
  ];
  lines.forEach((line, i) => {
    if (/\bsecret\b/.test(line.replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`/g, '""')) &&
        !allowedSecret.some((r) => r.test(line))) {
      v.push("line " + (i + 1) + " uses `secret` outside askPassword's five statements: " + line.trim());
    }
  });
  const gets = src.match(/heldPasswords\.get\(/g) || [];
  if (gets.length !== 1) v.push("heldPasswords.get appears " + gets.length + " times, not once");
  if (!/c\.sendRequest\("ermine\/preview\/connect", core\.connectRequest\(profile, heldPasswords\.get\(core\.profileKey\(profile\)\)\)\)/.test(src)) {
    v.push("the one read of the Map is not the argument of core.connectRequest in the connect request");
  }
  const sets = src.match(/heldPasswords\.set\(/g) || [];
  if (sets.length !== 1) v.push("heldPasswords.set appears " + sets.length + " times, not once");
  const bare = src.match(/heldPasswords(?!\.(has|get|set|delete|clear|keys)\()/g) || [];
  if (bare.length !== 1) v.push("heldPasswords is referenced " + bare.length + " times other than through its methods (only its declaration may)");
  if ((src.match(/const heldPasswords = new Map\(\);/g) || []).length !== 1) v.push("not exactly one `const heldPasswords = new Map();`");
  if ((src.match(/sendRequest\("ermine\/preview\/connect"/g) || []).length !== 1) v.push("not exactly one connect request");
  if ((src.match(/core\.connectRequest\(/g) || []).length !== 1) v.push("core.connectRequest is called other than once");
  // no sink ever sees either name
  lines.forEach((line, i) => {
    if (/\b(log|appendLine|postMessage|postSnapshot|showErrorMessage|showWarningMessage|showInformationMessage|setStatusBarMessage|update|writeFile\w*|writeTextFile)\(/.test(line) &&
        /\bsecret\b|heldPasswords|\bpassword\b(?!Prompt)/.test(line.replace(/"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`/g, '""'))) {
      v.push("line " + (i + 1) + " hands the password to a sink: " + line.trim());
    }
    if (/\b(globalState|workspaceState)\b/.test(line) && /\bsecret\b|heldPasswords/.test(line)) {
      v.push("line " + (i + 1) + " puts the password in a Memento");
    }
  });
  return v;
}

test("glue pins (WP-13): the password's one Map, one read, one write and no sink", () => {
  const raw = fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  assert.deepStrictEqual(passwordPins(raw), []);
});

test("glue pins (WP-13): one connect(), the model's effect order, the Running edge and the 503", () => {
  const raw = fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const src = codeOf(raw);
  const pin = (what) => "source pin (test/connect-core.test.js): extension.js changed shape — " + what;
  const body = (start, end) => {
    const i = src.indexOf(start);
    assert.ok(i >= 0, pin("no " + start));
    return src.slice(i, src.indexOf(end, i + start.length));
  };
  assert.strictEqual((src.match(/\nfunction connect\(cause\) \{/g) || []).length, 1, pin("not exactly one connect(cause)"));
  // A2: the profiles are read ONLY through inspect + userScopeProfilesCheck
  assert.ok(!/get\("preview\.profiles?"/.test(src), pin("a profile setting is read with get(), which honours workspace scope"));
  assert.ok(/core\.userScopeProfilesCheck\(config\(\)\.inspect\("preview\.profiles"\), config\(\)\.inspect\("preview\.profile"\)\)/.test(src),
            pin("the profiles are not read through core.userScopeProfilesCheck"));
  assert.ok(!/core\.profilesCheck\(/.test(src), pin("the glue calls profilesCheck directly, bypassing A2"));
  // every reducer call goes through a builder (the header's rule 1)
  const calls = src.match(/core\.connectReduce\(/g) || [];
  const built = src.match(/core\.connectReduce\(\s*connState,\s*core\.connectEvents\.\w+\(/g) || [];
  assert.strictEqual(calls.length, built.length, pin("a core.connectReduce call does not use core.connectEvents"));
  assert.ok(built.length >= 9, pin("only " + built.length + " connectReduce sites"));
  // every connectReduce result goes through applyConnect
  assert.strictEqual((src.match(/applyConnect\(\s*core\.connectReduce\(/g) || []).length, calls.length,
                     pin("a connectReduce result is not handed to applyConnect"));
  // the effect order the model applies
  const apply = body("function applyConnect(", "\n}\n");
  const order = ["fx.line", "fx.forget", "fx.sendDisconnect", "fx.prompt", "fx.send ", "fx.failed", "fx.retryIn", "!connState.retry", "fx.reconnect", "fx.rerender"];
  let at = -1;
  for (const e of order) {
    const j = apply.indexOf("if (" + e);
    assert.ok(j > at, pin("applyConnect's effects are not in the model's order at " + e));
    at = j;
  }
  assert.ok(/heldPasswords\.delete\(before\.key\)/.test(apply), pin("forget does not delete the key from BEFORE the event"));
  // A CONNECT IS NOT A RENDER: none of the connect functions touches the mark
  for (const name of ["function connect(", "function applyConnect(", "async function askPassword(", "async function sendConnect(",
                      "function sendDisconnect(", "function connectCommand(", "function disconnectCommand(",
                      "function onProfileSettingsChanged(", "function showConnectFailure("]) {
    const b = body(name, "\n}\n");
    assert.ok(!/guardReduce|applyGuard|wedgeMark|mayAutoRender/.test(b), pin(name + " consults or changes the wedge mark"));
  }
  const rerender = body("function rerenderAfterConnect(", "\n}\n");
  assert.ok(/core\.mayAutoRender\(wedgeMark, picked, trigger\)/.test(rerender) && /holdRender\(trigger\)/.test(rerender),
            pin("the re-render after a connect skips WP-22's consultation"));
  // the Running edge connects BEFORE applyStuck, and applyStuck defers
  const handlers = body("function installPreviewHandlers(", "\n}\n");
  const conn = handlers.indexOf('connect("running")');
  const stuck = handlers.indexOf("applyStuck(", conn);
  assert.ok(conn > 0 && stuck > conn, pin("the Running edge does not connect before applyStuck"));
  assert.ok(/onNotification\("ermine\/preview\/disconnected"/.test(handlers), pin("no disconnected handler"));
  const applyStuckBody = body("function applyStuck(", "\n}\n");
  assert.ok(/core\.connectEvents\.deferRender\(trigger\)/.test(applyStuckBody) && /if \(fx\.rerender && !deferred\)/.test(applyStuckBody),
            pin("applyStuck no longer defers its re-render to a pending connect"));
  // renderNow dresses the 503 before storing the answer
  const render = body("async function renderNow(", "\nasync function showAnswer(");
  const dress = render.indexOf("answer = core.dressNotConnected(answer, connState);");
  assert.ok(dress > 0 && dress < render.indexOf("lastAnswer = answer;"), pin("the 503 is not dressed before lastAnswer"));
  // the stop hook and the teardown
  assert.ok(/connRunning = false;\s*applyConnect\(core\.connectReduce\(connState, core\.connectEvents\.stopped\(\)\)\)/.test(body("function onClientStopped(", "\n}\n")),
            pin("onClientStopped does not tell the connect machine"));
  assert.ok(/heldPasswords\.clear\(\)/.test(body("function disposePreview(", "\n}\n")), pin("the teardown keeps the password"));
  // the commands are registered and declared
  const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "package.json"), "utf8"));
  const declared = pkg.contributes.commands.map((c) => c.command);
  for (const [id, title] of [[core.CONNECT_COMMAND, core.CONNECT_COMMAND_TITLE], [core.DISCONNECT_COMMAND, core.DISCONNECT_COMMAND_TITLE]]) {
    assert.ok(declared.includes(id), pin(id + " not in package.json"));
    assert.strictEqual(pkg.contributes.commands.find((c) => c.command === id).title, title);
    assert.ok(src.includes("registerCommand(core." + (id === core.CONNECT_COMMAND ? "CONNECT_COMMAND" : "DISCONNECT_COMMAND")), pin(id + " not registered"));
  }
  const props = pkg.contributes.configuration.properties;
  assert.ok(props["ermine.preview.profiles"] && props["ermine.preview.profile"], pin("the settings are not contributed"));
  // A1: the schema has no password property
  assert.deepStrictEqual(Object.keys(props["ermine.preview.profiles"].items.properties).sort(),
                         ["dialect", "driver", "id", "scanner", "url", "user"]);
  assert.strictEqual(props["ermine.preview.profiles"].items.additionalProperties, false);
});

test("A2: a workspace-scope profile is IGNORED and named; user scope wins; the mutant that honours it is killed", () => {
  // workspace only: no profile, no prompt, no send, the notice once, the status bar says so
  const w = glueModel();
  w.settings = { profiles: undefined, profile: undefined, trace: "off" };
  w.workspace = { profiles: [MSSQL], profile: "sales-mssql" };
  w.runningEdge();
  w.connectCommand();
  assert.deepStrictEqual([w.prompts.length, w.sent.length], [0, 0]);
  assert.strictEqual(w.logs.filter((l) => l.includes(core.SCOPE_NOTICE)).length, 1, "named once");
  assert.strictEqual(w.status.text, "$(database) workspace profiles ignored");
  assert.match(w.status.tooltip, /USER settings/);
  // both present: the USER value is the one used
  const b = glueModel();
  b.workspace = { profiles: [{ ...MSSQL, url: "jdbc:sqlserver://evil.example:1433" }], profile: "sales-mssql" };
  b.runningEdge();
  assert.strictEqual(b.prompts.length, 1);
  assert.match(b.prompts[0].text.prompt, /ermine @ 127\.0\.0\.1/);
  b.type(0, PASSWORD);
  assert.strictEqual(b.sent[0].profile.url, MSSQL_URL, "the password goes to the user's host only");
  // a workspace-only ACTIVE id does not pick a user profile either
  const id = glueModel();
  id.settings.profile = undefined;
  id.workspace = { profile: "sales-mssql" };
  id.runningEdge();
  assert.strictEqual(id.prompts.length, 0);
  assert.match(core.userScopeProfilesCheck({ globalValue: [] }, { workspaceFolderValue: "x" }).scopeNotice, /ignored/);
  assert.strictEqual(core.userScopeProfilesCheck({ globalValue: [MSSQL] }, { globalValue: "sales-mssql" }).scopeNotice, null);
  // MUTANT 'workspace value honoured': reads the effective value, as get() would
  const honour = (ip, ia) => {
    const eff = (i) => (i.workspaceValue !== undefined ? i.workspaceValue : i.globalValue);
    return core.profilesCheck(eff(ip), eff(ia));
  };
  const mut = glueModel({ checkFn: honour });
  mut.settings = { profiles: undefined, profile: undefined, trace: "off" };
  mut.workspace = { profiles: [{ ...MSSQL, url: "jdbc:sqlserver://evil.example:1433" }], profile: "sales-mssql" };
  mut.runningEdge();
  assert.ok(mut.prompts.length === 1 && /evil\.example/.test(mut.prompts[0].text.prompt),
            "the mutant must prompt for the hostile host, or this test proves nothing");
});

test("panel: the view's connection slot is the held connection's {id, dialect, host, database}, else null", () => {
  // the glue: `panelViewNow` passes `connection: core.panelConnection(connState)`
  const view = (m, answers) => core.panelView({ answers, connection: core.panelConnection(m.state) });
  const m = glueModel();
  assert.strictEqual(view(m).connection, null, "no profile");
  m.runningEdge();
  assert.strictEqual(view(m).connection, null, "prompting is not connected");
  m.type(0, PASSWORD);
  m.answer(0, OK);
  assert.deepStrictEqual(view(m).connection, { id: "sales-mssql", dialect: "mssql", host: "127.0.0.1", database: "ErmineSales" });
  // the Trace view's line joins host and database from it
  const traced = { ok: true, document: {}, generation: 1,
                   trace: { v: 1, generation: 1, wallMs: 5, phases: [], queries: [],
                            totals: { dbMs: 1, otherMs: 4, wallMs: 5 },
                            connection: { kind: "profile", dialect: "mssql", profile: "sales-mssql" } } };
  const t = view(m, { last: traced, good: traced }).trace;
  assert.ok(t && t.connection, "the panel's traceOf read the trace");
  assert.strictEqual(t.connection.host, "127.0.0.1");
  assert.strictEqual(t.connection.database, "ErmineSales");
  const text = JSON.stringify(view(m, { last: traced, good: traced }));
  assert.ok(!text.includes("databaseName=") && !text.includes("ermine\"") && !text.includes(PASSWORD), "never the url, user or password");
  // failed, disconnected, stopped: null
  m.connectCommand();
  m.answer(1, AUTH);
  assert.strictEqual(view(m).connection, null, "a failed connect");
  const d = connected();
  d.disconnectCommand();
  assert.strictEqual(view(d).connection, null, "disconnected");
  const st = connected();
  st.stopped();
  assert.strictEqual(view(st).connection, null, "the server stopped");
  // the pin: the glue passes exactly this, and re-posts on a change
  const src = codeOf(fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8"));
  const now = src.slice(src.indexOf("function panelViewNow("), src.indexOf("\n}\n", src.indexOf("function panelViewNow(")));
  assert.ok(/connection: core\.panelConnection\(connState\),/.test(now), "source pin: panelViewNow does not pass the connection");
  const apply = src.slice(src.indexOf("function applyConnect("), src.indexOf("\n}\n", src.indexOf("function applyConnect(")));
  assert.ok(/postSnapshot\("connection"\)/.test(apply), "source pin: applyConnect does not re-post the panel on a connection change");
});

// ----------------------------------------------- NEW-2: the bounded reconnect

const DOWN = { ok: false, class: "unreachable", kept: true, reason: "connect-unreachable",
               message: "SQLServerException: The TCP/IP connection to the host <host>, port 1433 has failed" };

/** Connected, a render sent, then the server drops the connection while the database is down. */
function downAfterConnect(opts) {
  const m = connected(opts);
  m.generation = 4;
  m.serverDisconnected("connection-lost");       // the one automatic attempt ...
  m.answer(m.sent.length - 1, DOWN);             // ... runs while the database is still down
  return m;
}

test("NEW-2: an unreachable failure retries after 5 s and 15 s, then stops: three attempts in all", () => {
  const m = downAfterConnect();
  assert.strictEqual(m.state.phase, "retrying");
  assert.strictEqual(m.status.text, "$(sync) sales-mssql: reconnecting (2/3)");
  const before = m.sent.length;
  m.tick(4999);
  assert.strictEqual(m.sent.length, before, "not before 5 s");
  m.tick(1);
  assert.strictEqual(m.sent.length, before + 1, "attempt 2 at 5 s, with the held password");
  assert.strictEqual(m.sent[before].body.password, PASSWORD);
  m.answer(before, DOWN);
  assert.strictEqual(m.status.text, "$(sync) sales-mssql: reconnecting (3/3)");
  m.tick(14999);
  assert.strictEqual(m.sent.length, before + 1);
  m.tick(1);
  assert.strictEqual(m.sent.length, before + 2, "attempt 3 at 15 s more");
  m.answer(before + 1, DOWN);
  assert.strictEqual(m.state.phase, "failed");
  assert.strictEqual(m.timer, null, "and it stops");
  m.tick(3600 * 1000);
  assert.strictEqual(m.sent.length, before + 2);
  assert.strictEqual(m.status.text, "$(database) sales-mssql: unreachable");
  assert.strictEqual(m.errors.length, 2, "notified on the chain's first and last failure only");
  assert.strictEqual(m.prompts.length, 1, "never a prompt");
});

test("NEW-2: `db.sh up` during the backoff: the retry connects and re-sends the last render ONCE", () => {
  const m = downAfterConnect();
  m.tick(5000);
  m.answer(m.sent.length - 1, OK);
  assert.strictEqual(m.state.phase, "connected");
  assert.deepStrictEqual(m.scheduled, [core.TRIGGER_RECONNECTED]);
  assert.strictEqual(m.timer, null);
});

test("NEW-2: a render while disconnected with a password held connects ONCE first; the banner only if that fails", () => {
  // after the chain gave up (the user ran `db.sh up` late), a render just works
  const m = downAfterConnect();
  m.tick(5000); m.answer(m.sent.length - 1, DOWN);
  m.tick(15000); m.answer(m.sent.length - 1, DOWN);
  assert.strictEqual(m.state.phase, "failed");
  const sent = m.sent.length;
  const panel = m.panel.length;
  m.render503();
  assert.deepStrictEqual(m.renders503, ["connect"]);
  assert.strictEqual(m.sent.length, sent + 1, "one connect");
  assert.strictEqual(m.panel.length, panel, "no banner yet");
  m.answer(sent, OK);
  assert.deepStrictEqual(m.scheduled, [core.TRIGGER_RECONNECTED], "and its success re-sends the render");
  // while connected a 503 (a race) shows the banner and connects nothing
  m.render503();
  assert.deepStrictEqual(m.renders503, ["connect", "banner"]);
  // if the render's connect fails, THEN the banner
  const f = downAfterConnect();
  f.tick(5000); f.answer(f.sent.length - 1, DOWN);
  f.tick(15000); f.answer(f.sent.length - 1, DOWN);
  const p = f.panel.length;
  f.render503();
  f.answer(f.sent.length - 1, DOWN);
  assert.strictEqual(f.panel.length, p + 1, "the banner, after the connect failed");
  assert.strictEqual(f.panel[f.panel.length - 1].reason, "connect-unreachable");
  // a render during the backoff takes the armed attempt now; the chain stays three
  const b = downAfterConnect();
  const n = b.sent.length;
  b.render503();
  assert.strictEqual(b.sent.length, n + 1);
  b.answer(n, DOWN);
  assert.strictEqual(b.status.text, "$(sync) sales-mssql: reconnecting (3/3)");
});

test("NEW-2: no retry for auth, kept:false, profile, without a held password, or after the user said no", () => {
  const a = connected();
  a.connectCommand();
  a.answer(1, AUTH);
  assert.deepStrictEqual([a.state.phase, a.timer], ["failed", null], "auth");
  const k = connected();
  k.connectCommand();
  k.answer(1, { ...DOWN, kept: false });
  assert.deepStrictEqual([k.state.phase, k.timer], ["failed", null], "kept:false");
  const p = connected();
  p.connectCommand();
  p.answer(1, { ok: false, class: "profile", kept: true, message: "x" });
  assert.strictEqual(p.timer, null, "profile");
  const d = connected();
  d.connectCommand();
  d.answer(1, { ok: false, class: "driver", kept: true, message: "x" });
  assert.strictEqual(d.state.phase, "retrying", "driver is retried (the brief)");
  // cancelled by Disconnect, a stop and a profile change
  for (const [what, act] of [["Disconnect", (m) => m.disconnectCommand()], ["stop", (m) => m.stopped()],
                             ["profile change", (m) => { m.settings.profile = "sales-sqlite"; m.settingsChanged(); }]]) {
    const m = downAfterConnect();
    const token = m.state.retry.token;
    act(m);
    const mssql = () => m.sent.filter((x) => x.profile.id === "sales-mssql").length;
    const n = mssql();
    assert.strictEqual(m.timer, null, what + " cancels the timer");
    m.apply(core.connectReduce(m.state, core.connectEvents.retryDue(token)));   // a timer that fired anyway
    for (let t = 0; t < 40; t++) m.tick(1000);
    assert.strictEqual(mssql(), n, what + ": no retry afterwards");
  }
  // a render with no password held never connects
  const r = downAfterConnect();
  r.held.clear();
  assert.strictEqual(core.renderMayConnect(r.state, r.canReconnect()), false);
  // nor after Disconnect / a declined prompt
  const u = connected();
  u.disconnectCommand();
  assert.strictEqual(core.renderMayConnect(u.state, true), false);
});

test("NEW-2 PROPERTY: no chain ever sends more than three attempts, whatever the clock and the answers", () => {
  let seed = 11;
  const rnd = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
  for (let run = 0; run < 300; run++) {
    const m = downAfterConnect();
    const start = m.sent.length - 1;                // attempt 1 of the chain
    for (let step = 0; step < 30; step++) {
      m.tick(rnd(20000));
      if (m.state.phase === "connecting" && rnd(4)) m.answer(m.sent.length - 1, DOWN);
    }
    assert.ok(m.sent.length - start <= core.RECONNECT_ATTEMPTS, "run " + run + ": " + (m.sent.length - start) + " attempts");
  }
});

test("MUTANT 'retry storm' (more than three) is killed", () => {
  // the mutant: a reducer whose chain never runs out
  const storm = (s, e) => {
    const r = core.connectReduce(Object.assign({}, s, { attempt: 1 }), e);
    return r;
  };
  const m = downAfterConnect({ reduce: storm });
  const start = m.sent.length - 1;
  for (let i = 0; i < 6; i++) { m.tick(15000); if (m.state.phase === "connecting") m.answer(m.sent.length - 1, DOWN); }
  assert.ok(m.sent.length - start > core.RECONNECT_ATTEMPTS, "the mutant must storm, or this test proves nothing");
  const real = downAfterConnect();
  const s0 = real.sent.length - 1;
  for (let i = 0; i < 6; i++) { real.tick(15000); if (real.state.phase === "connecting") real.answer(real.sent.length - 1, DOWN); }
  assert.strictEqual(real.sent.length - s0, core.RECONNECT_ATTEMPTS, "killed: the real chain is three");
});

test("MUTANT 'retry after Disconnect' is killed", () => {
  // the mutant: Disconnect forgets and tells the server, but leaves the chain armed
  const keepChain = (s, e) => {
    const r = core.connectReduce(s, e);
    if (e.type === "disconnect" && s.retry) r.state = Object.assign({}, r.state, { phase: "retrying", retry: s.retry });
    return r;
  };
  const m = downAfterConnect({ reduce: keepChain });
  m.disconnectCommand();
  const lines = m.logs.length;
  m.tick(5000);
  assert.ok(m.logs.slice(lines).some((l) => /connecting/.test(l)) && m.state.phase !== "idle",
            "the mutant must try to reconnect after Disconnect");
  const real = downAfterConnect();
  real.disconnectCommand();
  const r = real.sent.length;
  const rl = real.logs.length;
  real.tick(60000);
  assert.strictEqual(real.sent.length, r, "killed: nothing sent after Disconnect");
  assert.deepStrictEqual(real.logs.slice(rl), [], "killed: nothing even tried");
  assert.strictEqual(real.state.phase, "idle");
});

test("MUTANT 'a render trying to connect without a held password' is killed", () => {
  const mut = downAfterConnect({ renderAlways: true });
  mut.held.clear();
  mut.render503();
  assert.deepStrictEqual(mut.renders503, ["connect"], "the mutant tries");
  const real = downAfterConnect();
  real.held.clear();
  real.render503();
  assert.deepStrictEqual(real.renders503, ["banner"], "killed: the real code shows the banner");
  assert.strictEqual(real.prompts.length, 1, "and never prompts from a render");
});

test("glue pins (NEW-2): one backoff timer through the reducer, the render arm, and the teardown", () => {
  const src = codeOf(fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8"));
  const pin = (what) => "source pin (test/connect-core.test.js): extension.js changed shape — " + what;
  assert.strictEqual((src.match(/reconnectTimer = setTimeout\(/g) || []).length, 1, pin("not one backoff setTimeout"));
  assert.ok(/applyConnect\(core\.connectReduce\(connState, core\.connectEvents\.retryDue\(token\)\)\)/.test(src),
            pin("the timer does not hand its token back to the reducer"));
  assert.ok(/if \(fx\.retryIn !== null\) armReconnectTimer\(fx\.retryToken, fx\.retryIn\);\s*if \(!connState\.retry\) clearReconnectTimer\(\);/.test(src),
            pin("applyConnect does not arm/cancel the timer from the state"));
  assert.ok(/if \(fx\.reconnect\) connect\(fx\.reconnect\);/.test(src), pin("the reconnect cause is not the reducer's"));
  const render = src.slice(src.indexOf("async function renderNow("), src.indexOf("\nasync function showAnswer("));
  const arm = render.indexOf("if (core.isNotConnected(answer) && core.renderMayConnect(connState, canReconnectNow())) {");
  assert.ok(arm > 0 && arm < render.indexOf("answer = core.dressNotConnected(answer, connState);") &&
            /connect\("render"\);\s*setPreviewStatus\(\);\s*return;/.test(render.slice(arm, arm + 400)),
            pin("the render arm is not: ask core.renderMayConnect, connect once, return before the banner"));
  const can = src.slice(src.indexOf("function canReconnectNow("), src.indexOf("\n}\n", src.indexOf("function canReconnectNow(")));
  assert.ok(/return !active\.user \|\| heldPasswords\.has\(core\.profileKey\(active\)\);/.test(can),
            pin("canReconnectNow is not 'no user, or a password held'"));
  for (const name of ["answer", "rejected"]) {
    const calls = src.match(new RegExp("core\\.connectEvents\\." + name + "\\(", "g")) || [];
    const withFlag = src.match(new RegExp("core\\.connectEvents\\." + name + "\\([^;]*canReconnectNow\\(profile\\)|core\\.connectEvents\\." + name + "\\([^;]*, false\\)", "g")) || [];
    assert.strictEqual(withFlag.length, calls.length, pin("a connectEvents." + name + " call does not pass canReconnect"));
  }
  const teardown = src.slice(src.indexOf("function disposePreview("), src.indexOf("\n}\n", src.indexOf("function disposePreview(")));
  assert.ok(/clearReconnectTimer\(\)/.test(teardown), pin("the teardown leaves the backoff timer"));
});
