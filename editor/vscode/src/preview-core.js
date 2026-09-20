"use strict";

// The preview loop's DECISIONS, with no `require("vscode")` anywhere in this
// file (tracker/JSON-WIDGET-PLAYGROUND.md WP-7).
//
// Nothing in this repository runs VS Code, so the rules that could be got
// wrong -- which roots are sent, which answer is stale, whether a
// notification raises the stuck banner, when a save re-renders, what the
// two quick picks offer, what the status bar says -- live here as pure
// functions over plain data and are unit-tested under `node --test`
// (test/preview-core.test.js).  `src/extension.js` is the glue: it reads the
// editor's state, calls these, and does what they say.
//
// NOT EVERYTHING IS HERE, and the claim that it was has been struck (review
// D1): the tab's lifetime (when a document is created, revealed or left
// alone), the watcher's registration, the coalescing timer and the settings
// READS are glue decisions that need the editor to observe, and only their
// inputs and outputs are testable here.
//
// `path` is Node's own and has no editor in it, so it is allowed here.

const path = require("path");

// ----------------------------------------------------------------- roots

/**
 * `ermine.preview.roots` -> what goes on the wire (section 2.4).
 *
 * Every entry is made ABSOLUTE against the workspace folder that owns the
 * picked report, because a relative root would resolve against the SERVER's
 * working directory, which is the checkout `bin/ermine-lsp` runs in.
 *
 * A bad entry is REFUSED AND NAMED, never silently dropped and never sent:
 *  - a non-string, an empty or blank string: the server refuses both with a
 *    400 (`Preview.rootEntries`), so sending them would make every render
 *    fail; dropping them silently is the hazard that refusal exists to stop.
 *    They come back in `problems` and the caller says so out loud, once.
 * Duplicates are collapsed, order preserved: the server takes the list as a
 * loader chain and the FIRST root that has a module name wins, so the order
 * the developer wrote is the order sent.
 *
 * @param {unknown} entries the raw setting value
 * @param {string|undefined} folderPath the owning workspace folder, if any
 * @returns {{roots: string[], problems: string[]}}
 */
function absoluteRoots(entries, folderPath) {
  const roots = [];
  const problems = [];
  if (entries === undefined || entries === null) return { roots, problems };
  if (!Array.isArray(entries)) {
    return { roots, problems: ["ermine.preview.roots is an array of directory paths, not a " + typeName(entries)] };
  }
  for (const entry of entries) {
    if (typeof entry !== "string") {
      problems.push("ermine.preview.roots has an entry that is a " + typeName(entry) + "; each root is a directory path");
      continue;
    }
    const trimmed = entry.trim();
    if (!trimmed) {
      problems.push("ermine.preview.roots has an empty entry; each root is a directory path");
      continue;
    }
    // A NUL BYTE IS NOT A PATH ON ANY PLATFORM, and -- MEASURED on Node 24
    // while writing the test for it -- `path.resolve` does NOT refuse one:
    // it concatenates happily and the bad root goes on the wire, where the
    // server's own `Paths.get` refuses it as a 400 for every render. The
    // review asked for this to be caught here; the `try` below stays for
    // the platforms and future versions where `path` itself throws.
    if (trimmed.indexOf("\u0000") >= 0) {
      problems.push('ermine.preview.roots entry "' + printable(trimmed) +
                    '" is not a usable path: it contains a NUL byte');
      continue;
    }
    let absolute;
    try {
      if (path.isAbsolute(trimmed)) {
        absolute = path.normalize(trimmed);
      } else if (folderPath) {
        absolute = path.resolve(folderPath, trimmed);
      } else {
        problems.push('ermine.preview.roots entry "' + printable(trimmed) +
                      '" is relative and there is no workspace folder to resolve it against');
        continue;
      }
    } catch (err) {
      // `path.resolve`/`normalize` THROW on a string the platform cannot
      // hold -- a NUL byte is the reachable one (review S1). A setting the
      // developer typed must never take the command down with it.
      problems.push('ermine.preview.roots entry "' + printable(trimmed) + '" is not a usable path: ' +
                    (err && err.message ? String(err.message) : String(err)));
      continue;
    }
    if (!roots.includes(absolute)) roots.push(absolute);
  }
  return { roots, problems };
}

/** No control character from a setting reaches a log line or a message. */
function printable(value) {
  return String(value).replace(/[\u0000-\u001f\u007f]/g, "?");
}

function typeName(v) {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  return typeof v;
}

// -------------------------------------------------------------- the pick

/**
 * A pick is a (file, binding) PAIR (section 3.2), plus the module name the
 * server told us the file declares -- which is what `invalidated` names.
 * `module` is null when `ermine/preview/reports` could not answer (an
 * unreadable file, a header that does not parse) and the binding was typed
 * by hand: the pick still renders, it just cannot be matched against an
 * `invalidated` notification until the module is learned.
 */
function makePick(uri, fsPath, binding, moduleName, roots) {
  return {
    uri: String(uri),
    fsPath: String(fsPath),
    binding: String(binding),
    module: moduleName ? String(moduleName) : null,
    roots: Array.isArray(roots) ? roots.slice() : [],
  };
}

function pickLabel(pick) {
  if (!pick) return "no report picked";
  return (pick.module || path.basename(pick.fsPath)) + "." + pick.binding;
}

// ---------------------------------------------------------- the requests

/**
 * THE THREE REQUEST BUILDERS, together in one place for one reason (section
 * 6, Q7): `ermine/render` and `ermine/schema` must carry THE SAME `roots`
 * for the same pick.  The root set is the render session's discard key, so
 * a schema that disagrees with the render throws the session away and the
 * next render pays a boot.  Both read `pick.roots` and nothing else, and
 * `test/preview-core.test.js` asserts they are equal for every pick.
 */
function reportsParams(uri) {
  return { uri: String(uri) };
}

function renderParams(pick, params, generation) {
  return {
    uri: pick.uri,
    binding: pick.binding,
    // WP-7 SENDS NO PARAMS FILE (that is WP-8) AND SENDS `{}`, NOT `null`,
    // and the difference was MEASURED against a real server rather than
    // argued (scratchpad wp7-instrument.js on a copy of Sales.e):
    //   params: null -> 400 "expected an object (Query), found null" at
    //                   `$.params` -- which names no key at all;
    //   params: {}   -> 400 'the required key "fromDay" is missing' at
    //                   `$.params` -- which names the first key the
    //                   developer has to supply, and is what section 14's
    //                   done-when is after.
    // `{}` is also the better answer for a report whose parameters are all
    // optional: it DECODES and the report renders, where `null` refuses.
    params: params === undefined || params === null ? {} : params,
    roots: pick.roots.slice(),
    generation: generation,
  };
}

function schemaParams(pick) {
  return {
    uri: pick.uri,
    binding: pick.binding,
    roots: pick.roots.slice(),
  };
}

// ------------------------------------------------------------ generation

/**
 * Section 2.5: every render carries a counter and every answer echoes it;
 * an answer with an OLDER generation than the current one is discarded.
 *
 * A generation that is not a number is ACCEPTED, deliberately: the server
 * echoes `generation` as it arrived and answers `null` when it could not
 * read the request at all, and discarding those would hide exactly the
 * refusals the developer needs to see.  Only a number that is strictly
 * behind the current one is dropped.
 */
function isCurrentGeneration(current, answer) {
  const g = answer && typeof answer === "object" ? answer.generation : undefined;
  if (typeof g !== "number") return true;
  return g >= current;
}

// --------------------------------------------------------- the answers

function isOk(answer) {
  return !!(answer && typeof answer === "object" && answer.ok === true);
}

/**
 * ------------------------------------------------------------- the loop
 *
 * Q11 (section 3 step 6): re-render when the picked report's OWN file is
 * created or changed while its last answer was a PLACEMENT 404 -- one the
 * preview's front half decided before `Runner` was asked -- and NOT on a
 * `Runner` 404 ("no binding named X" on a module that DID load).
 *
 * THE TEST IS EXACT, and it is exact because the server was changed
 * (Q15, DECIDED by the user on 2026-09-20): a placement failure carries a
 * machine-readable `reason` from a closed vocabulary beside its `status`,
 * and a 404 out of the `Runner` carries no `reason` key at all. So this is
 * a test on two structured fields and matches no message text.
 *
 * NO DOUBLE RENDER IS POSSIBLE, by construction rather than by timing:
 *  - while a PLACEMENT 404 stands, the render session never loaded that
 *    module -- the file could not even be placed -- so
 *    `ermine/preview/invalidated` cannot name it and the watcher is the
 *    only trigger there is (that is Q11's whole reason for existing);
 *  - a RUNNER 404 carries no `reason`, so the watcher does nothing and
 *    `invalidated` owns the file, which is the case Q11's exclusion was
 *    written for.
 * The two triggers are therefore disjoint, and the coalescing window in
 * extension.js is not load-bearing for this (an earlier version of this
 * comment claimed it was; `invalidated` follows the server's own reload,
 * which is seconds, not milliseconds).
 *
 * COMPATIBILITY, stated because it is a silent difference: a server older
 * than Q15 sends no `reason` anywhere, so this reads every 404 as a
 * `Runner` 404 and the watcher never fires -- the extension degrades to
 * "no Q11 trigger", never to triggering wrongly.
 */
function isPlacement404(answer) {
  if (!answer || typeof answer !== "object") return false;
  if (answer.ok !== false) return false;
  return answer.status === 404 && typeof answer.reason === "string" && answer.reason.length > 0;
}

/**
 * The watcher's decision: a create or change event on the picked report's
 * own path, while its last answer was a placement 404.
 */
function shouldRerenderOnFileEvent(pick, lastAnswer, eventPath) {
  if (!pick) return false;
  // The watcher watches one path, but the decision says so too, so that an
  // event for anything else can never render.
  if (eventPath !== undefined && eventPath !== null && eventPath !== pick.fsPath) return false;
  return isPlacement404(lastAnswer);
}

/**
 * Section 3 step 6: re-render if the picked report's module is in the
 * `invalidated` set (which already includes dependents, so saving a widget
 * names every report that imports it). An unknown module matches nothing:
 * the extension re-asks `ermine/preview/reports` after a successful render
 * while it has none, which is how the pick recovers one.
 */
function shouldRerenderOnInvalidated(pick, modules) {
  if (!pick || !pick.module) return false;
  if (!Array.isArray(modules)) return false;
  return modules.indexOf(pick.module) >= 0;
}

// ----------------------------------------------------- the stuck state

/**
 * Section 4's four client rules for `ermine/preview/stuck {stuck, message,
 * seq}`, as a reducer over events:
 *
 *  (1) `seq` is monotonic per PROCESS and the two edges are sent by two
 *      threads with nothing ordering them, so the highest `seq` wins and
 *      anything at or below the high-water mark is ignored.  A `seq` that
 *      is not a number (an older server) is applied but does NOT move the
 *      mark -- this is the one place that departs from "highest wins", and
 *      it departs towards showing the state rather than hiding it.
 *  (2) the notification is AUTHORITATIVE.
 *  (3) the `"stuck": true` marker on an ANSWER is PER-REQUEST, not a state:
 *      it is applied only when no notification has arrived since that
 *      request was SENT (`seqAtSend`), so a stuck refusal decided before a
 *      clear cannot resurrect the banner.  A missing marker says nothing
 *      and never clears.
 *  (4) the `window/showMessage` beside each edge is ADVISORY and is not an
 *      event here at all: the extension registers no handler for it and
 *      lets VS Code show it, so no state can be derived from it.
 *
 * And DD-2: `seq` restarts at 1 in a fresh process, so the mark is RESET
 * when the language client enters `Running`.  Section 4 says "Stopped ->
 * Running"; vscode-languageclient passes through `Starting` on the way, so
 * the test here is "any transition INTO Running", which is the same
 * transition observed through the state the library actually reports.
 */
function initialStuckState() {
  return { stuck: false, message: null, highWater: 0, running: true };
}

const NO_EFFECTS = { raised: false, cleared: false, rerender: false, schema: false, offline: false, online: false };

function effects(over) {
  return Object.assign({}, NO_EFFECTS, over);
}

function stuckReduce(state, event) {
  const s = state || initialStuckState();
  if (!event || typeof event !== "object") return { state: s, effects: effects({}) };

  if (event.type === "notification") {
    const seq = event.seq;
    let highWater = s.highWater;
    if (typeof seq === "number") {
      if (seq <= s.highWater) return { state: s, effects: effects({}) };  // rule (1)
      highWater = seq;
    }
    const stuck = event.stuck === true;
    const next = { stuck, message: stuck ? messageOf(event) : null, highWater, running: s.running };
    return {
      state: next,
      effects: effects({
        raised: stuck && !s.stuck,
        // THE TOAST is gated on having shown a banner -- "the preview
        // recovered" is meaningless if nothing ever said it was stuck.
        cleared: !stuck && s.stuck,
        // THE RE-RENDER IS NOT (review DM-2). The client can miss the
        // rising edge entirely and still need this: the wedged job's ANSWER
        // is sent before `{stuck:true}`, `{stuck:false}` comes from another
        // thread and §4 rule (1) says it can overtake -- so an accepted
        // clear may be the FIRST edge this client ever sees, with a stuck
        // refusal already in the tab and every `invalidate` of the wedge
        // dropped. The server never sends a gratuitous clear (Q10's
        // recovery runs only when the state really was set), so an accepted
        // `{stuck:false}` always means "re-render, you are behind".
        rerender: !stuck,
        schema: !stuck,
      }),
    };
  }

  if (event.type === "answer") {
    if (event.stuck !== true) return { state: s, effects: effects({}) };   // rule (3)
    if (s.highWater !== event.seqAtSend) return { state: s, effects: effects({}) };
    const next = { stuck: true, message: messageOf(event), highWater: s.highWater, running: s.running };
    return { state: next, effects: effects({ raised: !s.stuck }) };
  }

  if (event.type === "clientState") {
    if (event.to === "Running") {
      const next = { stuck: false, message: null, highWater: 0, running: true };
      return {
        state: next,
        effects: effects({
          cleared: s.stuck,
          online: !s.running,
          // Section 5's "Server stopped" row: on Running, re-send the last
          // render.  Only after a stop -- the first Running of a session has
          // no last render to re-send and the glue would skip it anyway.
          rerender: !s.running,
          schema: !s.running,
        }),
      };
    }
    if (event.to === "Stopped") {
      return {
        state: { stuck: s.stuck, message: s.message, highWater: s.highWater, running: false },
        effects: effects({ offline: s.running }),
      };
    }
    return { state: s, effects: effects({}) };
  }

  return { state: s, effects: effects({}) };
}

function messageOf(event) {
  return typeof event.message === "string" && event.message ? event.message : "the preview is stuck";
}

// ------------------------------------------------------------- settings

const TIMEOUT_MIN = 0;
const TIMEOUT_MAX = 3600;
const BYTES_MIN = 1024;
const BYTES_MAX = Math.pow(2, 40);

/**
 * The two settings the server reads (`Preview.applySettings`), validated
 * here with the server's own bounds so a value it would refuse is named in
 * the editor where it was typed rather than only in the server log.  An
 * out-of-range or ill-typed value is DROPPED from the payload -- the server
 * keeps its default -- and named in `problems`.
 */
function previewSettings(raw) {
  const out = {};
  const problems = [];
  const t = raw ? raw.timeoutSeconds : undefined;
  if (t !== undefined && t !== null) {
    if (typeof t !== "number" || !isFinite(t) || Math.floor(t) !== t) {
      problems.push("ermine.preview.timeoutSeconds is a whole number of seconds, not a " + typeName(t));
    } else if (t < TIMEOUT_MIN || t > TIMEOUT_MAX) {
      problems.push("ermine.preview.timeoutSeconds of " + t + " is outside 0..3600 and was not sent");
    } else {
      out.timeoutSeconds = t;
    }
  }
  const b = raw ? raw.maxDocumentBytes : undefined;
  if (b !== undefined && b !== null) {
    if (typeof b !== "number" || !isFinite(b) || Math.floor(b) !== b) {
      problems.push("ermine.preview.maxDocumentBytes is a whole number of bytes, not a " + typeName(b));
    } else if (b < BYTES_MIN || b > BYTES_MAX) {
      problems.push("ermine.preview.maxDocumentBytes of " + b + " is outside 1KiB..1TiB and was not sent");
    } else {
      out.maxDocumentBytes = b;
    }
  }
  return { preview: out, problems };
}

/**
 * `initialize` and a settings push DO NOT AGREE about the spelling, and
 * section 2.4 says the extension must send both:
 *
 *  - `initializationOptions` is already the server's own object, so the
 *    preview settings sit at `initializationOptions.preview.*` with NO
 *    `ermine` wrapper, exactly as `fastMode` and `debounce` do;
 *  - `workspace/didChangeConfiguration` is read as `settings.ermine.*`
 *    first and `settings.*` second, so the wrapped shape is what we send.
 */
function initializationOptions(values) {
  const { preview } = previewSettings(values);
  const options = { fastMode: !!(values && values.fastMode) };
  if (Object.keys(preview).length) options.preview = preview;
  return options;
}

function didChangeConfigurationParams(values) {
  const { preview } = previewSettings(values);
  const ermine = { fastMode: !!(values && values.fastMode) };
  if (Object.keys(preview).length) ermine.preview = preview;
  return { settings: { ermine } };
}

/**
 * `ermine.maxHeap` -> the `ERMINE_LSP_XMX` environment variable the
 * launcher reads (`bin/ermine-lsp:78-96`).
 *
 * THE VALUE IS VALIDATED HERE, with the launcher's own two tests -- the
 * spelling `^[1-9][0-9]*[kKmMgGtT]$` and the 64m floor -- and a value that
 * fails either is NOT EXPORTED.  The outcome is the launcher's own (2g),
 * and the difference is where the developer is told: the launcher's refusal
 * goes to the server's stderr, which is not where anyone who just typed a
 * setting is looking.  Passing it through unchecked was the alternative and
 * is what this rejects.
 */
const XMX_SPELLING = /^[1-9][0-9]*[kKmMgGtT]$/;

function heapEnvironment(maxHeap) {
  if (maxHeap === undefined || maxHeap === null) return { env: {}, problem: null };
  const value = String(maxHeap).trim();
  if (!value) return { env: {}, problem: null };
  if (!XMX_SPELLING.test(value)) {
    return {
      env: {},
      problem: 'ermine.maxHeap "' + value + '" is not a JVM heap size (a non-zero number and a k, m, g or t suffix, e.g. 2g, 512m); the server uses its own default of 2g',
    };
  }
  const digits = value.slice(0, -1);
  const suffix = value.slice(-1).toLowerCase();
  const small =
    digits.length <= 18 &&
    ((suffix === "k" && Number(digits) < 65536) || (suffix === "m" && Number(digits) < 64));
  if (small) {
    return {
      env: {},
      problem: 'ermine.maxHeap "' + value + '" is below the launcher\'s 64m floor (the resident session cannot boot in a heap that small); the server uses its own default of 2g',
    };
  }
  return { env: { ERMINE_LSP_XMX: value }, problem: null };
}

// ------------------------------------------------------------- the tab

/**
 * What goes in the untitled JSON tab.  A good answer shows THE DOCUMENT --
 * the command is "Render Report to JSON" and the document is the JSON; a
 * refusal shows the WHOLE `{ok:false, ...}` answer, because `status`,
 * `message` and `path` together are the diagnostic (the done-when is the
 * 400 that names `$.params.fromDay`, which lives in `path`).
 */
function tabContent(answer) {
  if (answer === undefined) return "";
  if (isOk(answer)) return stringify(answer.document);
  return stringify(answer);
}

function stringify(value) {
  try {
    return JSON.stringify(value, null, 2);
  } catch (err) {
    return JSON.stringify({ error: "the answer could not be printed: " + String(err && err.message ? err.message : err) }, null, 2);
  }
}

/**
 * A render can also fail as a JSON-RPC ERROR rather than an answer: section
 * 2.5's `-32800` for a render this one displaced, a cancelled one, and the
 * shutdown drain.  `-32800` is NOT shown -- a newer render is already on
 * its way and its answer is the one the tab wants -- and everything else is
 * dressed as an answer so the tab can show it.
 */
const REQUEST_CANCELLED = -32800;

function isDisplaced(err) {
  return !!(err && (err.code === REQUEST_CANCELLED || (err.data && err.data.code === REQUEST_CANCELLED)));
}

function errorAnswer(err, generation) {
  return {
    ok: false,
    status: err && typeof err.code === "number" ? err.code : null,
    message: err && err.message ? String(err.message) : String(err),
    generation: generation,
  };
}

// ----------------------------------------------------------- the picker

/**
 * The file step of section 3.2's picker, as a list. The active editor's
 * file comes FIRST and is offered even when the workspace scan missed it (a
 * report under a preview root outside the folders is still a report); the
 * rest are sorted by file name, then by path, so two `Sales.e` under
 * different directories are next to each other and told apart by their
 * description.
 *
 * `files` and `active` are `{fsPath, relative}` -- the glue turns a `Uri`
 * into that, so nothing here knows about the editor.
 */
function pickerItems(files, active) {
  const items = [];
  const seen = new Set();
  const add = (f) => {
    if (!f || typeof f.fsPath !== "string" || seen.has(f.fsPath)) return;
    seen.add(f.fsPath);
    items.push({ label: path.basename(f.fsPath), description: f.relative || f.fsPath, fsPath: f.fsPath });
  };
  const isErmine = active && typeof active.fsPath === "string" && /\.e$/.test(active.fsPath);
  if (isErmine) add(active);
  const rest = [];
  for (const f of files || []) {
    if (!f || typeof f.fsPath !== "string" || seen.has(f.fsPath)) continue;
    seen.add(f.fsPath);
    rest.push({ label: path.basename(f.fsPath), description: f.relative || f.fsPath, fsPath: f.fsPath });
  }
  rest.sort((a, b) => a.label.localeCompare(b.label) || a.description.localeCompare(b.description));
  return items.concat(rest);
}

const TYPE_A_BINDING = "$(edit) Type a binding name\u2026";

/**
 * The binding step: what `ermine/preview/reports` listed, `binding : type`,
 * and ALWAYS a free-text entry last -- the filter is a candidate list
 * (§3.2) and a binding that is not a report is a 400 at render, not a thing
 * to hide from the picker.
 */
function bindingItems(reports, error) {
  const listed = (Array.isArray(reports) ? reports : []).map((r) => ({
    label: String(r && r.binding),
    description: String((r && r.type) || ""),
    binding: String(r && r.binding),
  }));
  listed.push({
    label: TYPE_A_BINDING,
    description: listed.length
      ? "any top-level binding, report-typed or not"
      : error
        ? "the server could not list this file: " + error
        : "no report-typed binding was found in this file",
    binding: null,
  });
  return listed;
}

// -------------------------------------------------------- the status bar

/**
 * What the preview's status bar item says, as a function of the state.
 *
 * THE PRECEDENCE MATTERS AND IS TESTED (review IM-3): **not running beats
 * stuck**. §2.5 measured that a wedged server exits about two minutes after
 * the watchdog fires, so "stuck" and "the process is gone" is a state the
 * user really reaches -- and "preview: stuck" would then be advice to press
 * a Restart button on a server that is already restarting, or permanently
 * wrong if the restart failed.
 */
function statusBarState(view) {
  const v = view || {};
  const label = pickLabel(v.pick);
  if (!v.pick && !v.stuck && v.running !== false) return { hidden: true };
  if (v.running === false) {
    return {
      hidden: false,
      text: "$(debug-disconnect) Ermine: preview offline",
      tooltip: "the language server stopped; the last document is kept",
      severity: "warning",
    };
  }
  if (v.stuck) {
    return {
      hidden: false,
      text: "$(warning) Ermine preview: stuck",
      tooltip: v.message || "the preview is stuck",
      severity: "warning",
    };
  }
  if (v.rendering) {
    return { hidden: false, text: "$(sync~spin) Ermine: " + label, tooltip: "rendering", severity: "none" };
  }
  const roots = v.pick && v.pick.roots && v.pick.roots.length ? v.pick.roots.join(", ") : "(none configured)";
  const tooltip = v.pick
    ? v.pick.fsPath + "\nbinding: " + v.pick.binding + "\nroots: " + roots +
      (v.pick.module ? "" : "\nthe module name is unknown, so `invalidated` cannot match it")
    : "no report picked";
  return { hidden: false, text: "$(json) Ermine: " + label, tooltip, severity: "none" };
}

module.exports = {
  absoluteRoots,
  makePick,
  pickLabel,
  reportsParams,
  renderParams,
  schemaParams,
  isCurrentGeneration,
  isOk,
  isPlacement404,
  shouldRerenderOnFileEvent,
  shouldRerenderOnInvalidated,
  initialStuckState,
  stuckReduce,
  previewSettings,
  initializationOptions,
  didChangeConfigurationParams,
  heapEnvironment,
  pickerItems,
  bindingItems,
  TYPE_A_BINDING,
  statusBarState,
  tabContent,
  isDisplaced,
  errorAnswer,
  REQUEST_CANCELLED,
};
