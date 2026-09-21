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
// `crypto` is Node's own, like `path`: no editor in it, so the digest the
// wedge mark stores (WP-22 review M3) can be computed here and tested here.
const crypto = require("crypto");

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

// ------------------------------------------------------- the wedge guard
//
// WP-22 (section 14, Q13's re-decision, Q17).  THE USER'S PRINCIPLE, in
// their words: "We'd want some sort of confirmation before rendering a
// report which wedged and was killed the first time around and it didn't
// change", and "I think 'remembering' is an extension concern".
//
// THE LOOP THIS EXISTS FOR, read from the code and UNOBSERVED in any
// editor: a render wedges the preview; the watchdog answers it and marks
// the preview stuck; the wedged evaluation keeps allocating until the JVM
// hits -Xmx and exits; vscode-languageclient restarts the server; the
// transition back into `Running` makes `stuckReduce` ask for a re-render
// (`rerender: !s.running` above) -- of the very report that killed the
// last process.  The SAME path is taken by the **Restart Language Server**
// button in our own stuck notification, so the one remedy offered during a
// wedge is itself a loop trigger.
//
// THE GUARD IS ONE MARK AND ONE CONSULTATION.
//
//   THE MARK is `{key, reason, at, rootsFingerprint, paramsFingerprint}`
//   for the CURRENT pick and for no other -- never a map, because a map is
//   an unbounded structure nobody ever clears.  Roots and params live in
//   the VALUE, so changing either CLEARS the mark rather than minting a
//   second one.
//
//   THE CONSULTATION is `shouldAutoRender`, and the glue calls it at
//   EXACTLY ONE SITE: the `rerender` effect of the Stopped -> Running
//   transition.  Every other automatic trigger is left alone, on purpose:
//   `invalidated` (the server's own dependency closure), the Q11 watcher
//   (the picked file changed), a roots change (the developer edited the
//   setting) and `{stuck:false}` (the job CAME BACK -- it was slow, not
//   wedged) are each evidence of change or of recovery.  The picker, the
//   render command and "Render anyway" are consent.
//
// "IT DIDN'T CHANGE" IS A PROXY, NOT A PROOF, and the tracker says so in
// the same words: the wedge is usually in a DEPENDENCY, so a content hash
// of the picked file would be wrong.  The two signals used -- the server's
// own `invalidated`, and any `.e` save -- err towards asking LESS.
//
// `stuckReduce` IS NOT TOUCHED.  It carries section 4's four client rules,
// DD-2 and its own pinned properties; this is a reducer of its own over a
// separate piece of state.  The one place they could have disagreed is
// pinned instead: `stuckEventApplies` is exactly rule (1)/(3)'s acceptance
// test, the glue feeds its answer to `guardReduce` as `applies`, and a
// property here asserts it agrees with `stuckReduce` event for event.  Without
// it a STALE `{stuck:false}` -- one `stuckReduce` ignores because its `seq`
// is at or below the high-water mark -- would clear a mark that the banner
// still says is live.

/** The mark's key: the pick's identity, and nothing else. */
const MARK_SEPARATOR = "␟";

/** The closed reason vocabulary. A restored value carrying anything else is not a mark. */
const WEDGE_WATCHDOG = "watchdog";
const WEDGE_DIED_MID_RENDER = "died-mid-render";
const WEDGE_REASONS = [WEDGE_WATCHDOG, WEDGE_DIED_MID_RENDER];

/**
 * The ONE trigger the mark is consulted for.  It is a constant rather than
 * a string literal at the call site so that a typo cannot silently turn the
 * guard off: every other trigger name means "not consulted", which is the
 * safe direction for everything except this one.
 */
const TRIGGER_RESTART = "restart";

function markKey(pick) {
  if (!pick || typeof pick !== "object") return null;
  if (pick.uri === undefined || pick.binding === undefined) return null;
  return String(pick.uri) + MARK_SEPARATOR + String(pick.binding);
}

/**
 * A canonical string for a plain value: object keys sorted, so the same
 * params in a different key order fingerprint the same.  Anything JSON
 * cannot hold (a function, a symbol, `undefined`, NaN) becomes `null`,
 * which is what `JSON.stringify` does on the wire anyway.
 */
function canonicalJson(value) {
  if (value === null || value === undefined) return "null";
  const t = typeof value;
  if (t === "function" || t === "symbol") return "null";
  if (t !== "object") {
    const s = JSON.stringify(value);
    return s === undefined ? "null" : s;
  }
  if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
  const keys = Object.keys(value).sort();
  return "{" + keys.map((k) => JSON.stringify(k) + ":" + canonicalJson(value[k])).join(",") + "}";
}

/**
 * A FINGERPRINT IS A DIGEST, NOT THE VALUE (WP-22 review M3).
 *
 * The mark is written into `workspaceState`, so whatever a fingerprint
 * holds is persisted on the developer's disk.  `paramsFingerprint` is
 * WP-8's hook and WP-8 will hand it the params it actually sends -- a
 * connection string with a password in it, among other things -- and
 * `rootsFingerprint` holds absolute paths that `PICK_KEY` does not persist
 * today.  Neither is ever compared to anything but another fingerprint, so
 * a SHA-256 of the canonical form does the whole job and stores nothing.
 *
 * THE UNFINGERPRINTABLE CASE HOLDS, DELIBERATELY, and the comment that used
 * to stand here said the opposite of what the code does (review §5). A
 * cyclic or absurdly deep value answers ONE fixed sentinel, so two of them
 * compare EQUAL and the guard does NOT clear: the mark stands and the user
 * is asked. That is the safe direction -- a spurious question costs one
 * click, and a clear we cannot justify re-renders a wedge.
 *
 * `Date`s (and every other object with no own enumerable keys) canonicalise
 * as `{}`, so two different `Date`s fingerprint the same. Unreachable from
 * JSON params, recorded rather than fixed.
 */
const UNFINGERPRINTABLE = "\u0000unfingerprintable";

function digest(text) {
  return crypto.createHash("sha256").update(String(text), "utf8").digest("hex");
}

function fingerprint(value) {
  let canonical;
  try {
    canonical = canonicalJson(value);
  } catch (err) {
    canonical = UNFINGERPRINTABLE;
  }
  return digest(canonical);
}

/** The roots are a loader CHAIN, so their order is part of the value. */
function rootsFingerprint(roots) {
  return fingerprint(Array.isArray(roots) ? roots.map(String) : []);
}

/**
 * WP-8's hook, exported now and fed later: no params exist until WP-8, so
 * today every mark carries the fingerprint of `{}` and a params change can
 * never be observed.  WP-8 passes the params it actually sends.
 */
function paramsFingerprint(params) {
  return fingerprint(params === undefined || params === null ? {} : params);
}

/** A value is a mark only if every field is the shape the guard wrote. */
function isMark(value) {
  return !!(
    value &&
    typeof value === "object" &&
    typeof value.key === "string" && value.key.length > 0 &&
    typeof value.reason === "string" && WEDGE_REASONS.indexOf(value.reason) >= 0 &&
    (value.at === null || typeof value.at === "number") &&
    typeof value.rootsFingerprint === "string" &&
    typeof value.paramsFingerprint === "string"
  );
}

/** Is this mark the CURRENT pick's? A mark for any other pick is never consulted. */
function markMatches(mark, pick) {
  const key = markKey(pick);
  return !!(isMark(mark) && key !== null && mark.key === key);
}

const NO_GUARD_EFFECTS = { set: false, cleared: false, restored: false, reason: null, why: null, label: null };

function guardEffects(over) {
  return Object.assign({}, NO_GUARD_EFFECTS, over);
}

/**
 * THE MARK'S WHOLE LIFECYCLE, as a reducer over plain events.  `at` comes
 * IN with the event (the glue passes `Date.now()`), so this file holds no
 * clock and every case is a table test.
 *
 * SET
 *   answer        `{stuck:true, applies}` for the current pick  -> "watchdog"
 *   notification  `{stuck:true, applies}`                       -> "watchdog"
 *   clientState   `Stopped` while a render was in flight        -> "died-mid-render"
 * CLEAR
 *   notification  `{stuck:false}` -- the job came back; LOAD-BEARING, without
 *                 it a 300 s scan under a 60 s watchdog is held for ever
 *   invalidated   naming the pick's module
 *   save          any `.e` document
 *   pick          any pick change
 *   roots         when the fingerprint differs
 *   params        when the fingerprint differs (WP-8)
 *   render        an explicit one: the picker, the render command,
 *                 "Render anyway" -- that IS the confirmation
 *   restore       a persisted mark whose key or roots do not match the
 *                 restored pick
 *
 * SET IS IDEMPOTENT FOR A KEY: `{stuck:true}` and the wedged ANSWER arrive
 * in either order (MEASURED over the wire: the answer came first in every
 * run), and the server may die before the watchdog fires or after it, so
 * the same incident can present two or three times.  The FIRST mark for a
 * key stands, keeping its `at` and its reason; only a mark for a different
 * pick is replaced.
 *
 * `applies` IS RULE (1)/(3)'s ANSWER, computed by `stuckEventApplies` from
 * the stuck state BEFORE `stuckReduce` sees the event.  An event
 * `stuckReduce` ignores must not move the mark either, or the banner and
 * the guard would describe different worlds.
 */
function guardReduce(mark, event) {
  const m = isMark(mark) ? mark : null;
  const keep = { mark: m, effects: guardEffects({}) };
  if (!event || typeof event !== "object") return keep;

  const pick = event.pick;
  const key = markKey(pick);

  const clear = (why) => (m ? { mark: null, effects: guardEffects({ cleared: true, why }) } : keep);
  const set = (reason) => {
    if (key === null) return keep;                  // nothing is picked: nothing to mark
    if (m && m.key === key) return keep;            // the first mark for this pick stands
    return {
      mark: {
        key,
        reason,
        at: typeof event.at === "number" ? event.at : null,
        rootsFingerprint: rootsFingerprint(pick && pick.roots),
        paramsFingerprint: paramsFingerprint(event.params),
      },
      // The LABEL OF THE PICK THAT WAS MARKED, because it is not always the
      // current one: a stuck answer marks the pick captured at send (N2),
      // and the glue's log line must name that one rather than whatever is
      // picked when the event lands.
      effects: guardEffects({ set: true, reason, label: pickLabel(pick) }),
    };
  };

  switch (event.type) {
    case "answer":
      // Rule (3): the marker on an answer is PER REQUEST. A refusal decided
      // before a clear must not raise the banner, and must not mark either.
      if (event.stuck !== true || event.applies === false) return keep;
      return set(WEDGE_WATCHDOG);

    case "notification":
      if (event.applies === false) return keep;
      if (event.stuck === true) return set(WEDGE_WATCHDOG);
      return clear("the preview recovered: the wedged job returned");

    case "clientState":
      // The server died while a render of the pick was in flight. It may
      // never have fired the watchdog at all -- at a small -Xmx the JVM
      // exits first (MEASURED: WpBlow at 256m, exit 3 at 8.6 s, no fire).
      if (event.to === "Stopped" && event.renderInFlight === true) return set(WEDGE_DIED_MID_RENDER);
      return keep;

    case "invalidated":
      // The server's own dependency closure named the pick's module.
      return shouldRerenderOnInvalidated(pick, event.modules)
        ? clear("the server invalidated " + String(pick.module))
        : keep;

    case "save":
      // The fallback `invalidated` cannot give: while the server is DEAD
      // nothing sends `didChangeWatchedFiles`, so no notification can cover
      // the window in which the developer fixes the loop. Deliberately
      // imprecise -- it errs towards asking less.
      return typeof event.path === "string" && /\.e$/.test(event.path)
        ? clear("an Ermine source file was saved")
        : keep;

    case "pick":
      return clear("the pick changed");

    case "roots":
      if (!m) return keep;
      if (m.key !== key) return clear("the mark belongs to another pick");
      return m.rootsFingerprint !== rootsFingerprint(pick && pick.roots)
        ? clear("ermine.preview.roots changed")
        : keep;

    case "params":
      if (!m) return keep;
      if (key !== null && m.key !== key) return clear("the mark belongs to another pick");
      return m.paramsFingerprint !== paramsFingerprint(event.params)
        ? clear("the parameters changed")
        : keep;

    case "render":
      // T1, T2 and "Render anyway". Asking for it IS the confirmation.
      return event.explicit === true ? clear("the user asked for this render") : keep;

    case "restore": {
      // Activation: `workspaceState` hands back whatever was written last.
      const saved = isMark(event.mark) ? event.mark : null;
      if (!saved) return { mark: null, effects: guardEffects({}) };
      if (key === null || saved.key !== key) {
        return { mark: null, effects: guardEffects({ cleared: true, why: "the remembered mark is not this pick's" }) };
      }
      if (saved.rootsFingerprint !== rootsFingerprint(pick && pick.roots)) {
        return { mark: null, effects: guardEffects({ cleared: true, why: "ermine.preview.roots changed while the window was closed" }) };
      }
      // N4: a restore is NOT a fresh incident, and the glue must not say
      // it is. `restored` is what tells the two apart in the channel.
      return { mark: saved, effects: guardEffects({ set: true, restored: true, reason: saved.reason, label: pickLabel(pick) }) };
    }

    default:
      return keep;
  }
}

/**
 * Rule (1) and rule (3)'s acceptance test, so that the guard and the stuck
 * banner cannot disagree about whether an event happened.  It is the ONE
 * thing this file states twice, and the duplication is pinned by a property
 * ("the guard and the stuck reducer accept exactly the same events").
 */
function stuckEventApplies(state, event) {
  const s = state || initialStuckState();
  if (!event || typeof event !== "object") return false;
  // EXACTLY `stuckReduce`'s own test, as its negation rather than as its
  // mirror image (WP-22 review §2): `<=` and `>` are NOT complements at
  // NaN, and a `{seq: NaN}` notification is applied by `stuckReduce` (it
  // poisons `highWater`) while `seq > highWater` would have said no. JSON
  // cannot carry NaN, so this is latent rather than live -- but "exactly"
  // was claimed here, and now it is true.
  if (event.type === "notification") return !(typeof event.seq === "number" && event.seq <= s.highWater);
  if (event.type === "answer") return event.stuck === true && s.highWater === event.seqAtSend;
  return false;
}

/**
 * THE ONE CONSULTATION.  `trigger` names which of section 3/5's render
 * triggers is asking; only the restart one is ever refused, and only for a
 * mark that is THIS pick's.
 */
function shouldAutoRender(mark, pick, trigger) {
  if (trigger !== TRIGGER_RESTART) return true;
  return !markMatches(mark, pick);
}

function heldPhrase(reason) {
  return reason === WEDGE_DIED_MID_RENDER
    ? "was still rendering when the language server stopped"
    : "wedged the preview: the watchdog fired and the server did not come back";
}

/**
 * The text of the one non-modal warning, and `null` when there is nothing
 * to ask about -- a mark that is not this pick's is never consulted and
 * never spoken about.
 */
function heldMessage(mark, pick) {
  if (!markMatches(mark, pick)) return null;
  return (
    "Ermine: " + pickLabel(pick) + " " + heldPhrase(mark.reason) +
    ". Nothing has changed since, so it was NOT re-rendered automatically."
  );
}

/**
 * M1 (WP-22 review). DOES THIS REJECTION MEAN THE SERVER WENT AWAY?
 *
 * `renderNow` awaits `sendRequest`. When the server dies mid-render the
 * promise rejects AND the client reports `Stopped`, and WHICH OF THE TWO
 * THE GLUE SEES FIRST IS DECIDED INSIDE `vscode-languageclient`, which
 * nothing here can observe and whose source is not read (the standing
 * rule). The guard must therefore not depend on the order: the in-flight
 * fact is cleared only by a SETTLED RESULT, and the rejection path marks
 * the wedge itself. `guardReduce`'s SET is idempotent per key, so doing it
 * from both places is safe.
 *
 * THIS PREDICATE IS THE ONLY PLACE THE QUESTION IS ANSWERED, and it is
 * deliberately asymmetric: a shape we can justify from a PUBLISHED
 * SPECIFICATION means the peer answered; **everything else -- every shape
 * we cannot name -- means the server went away**, and marks. A spurious
 * "held" costs one click; a missed one re-renders a report that killed the
 * last process.
 *
 * DOCUMENTED (JSON-RPC 2.0 §5.1, and the LSP specification's error codes):
 *   -32700 parse error, -32600 invalid request, -32601 method not found,
 *   -32602 invalid params;
 *   -32002 ServerNotInitialized, -32001 UnknownErrorCode,
 *   -32800 RequestCancelled, -32801 ContentModified,
 *   -32802 ServerCancelled, -32803 RequestFailed.
 * Each of those is an answer a PEER composes, so the connection was alive.
 *
 * **-32603 IS NOT IN THAT LIST, AND THE REASON IS THIS SERVER** (found by
 * the WP-22 delta review, READ in the Scala, `file:line` because it decides
 * the behaviour): `Rpc.InternalError` IS -32603 (`Rpc.scala:252`), and
 * `Preview.scala:207-208` pre-allocates `crashAnswer = Left((InternalError,
 * "the preview failed"))` for exactly one situation -- the preview THREAD
 * died. `rescueInFlight` (`:1263`) hands it to the render that was in
 * flight, `drainOnDeath` (`:1277`) to everything queued behind it, and
 * `:523`/`:614` answer every LATER render "the preview thread is not
 * running" with the same code. A FATAL error kills that thread without
 * touching the JVM (`isFatal`, `:1086`: any `Error`, so a
 * `StackOverflowError` out of a runaway recursive evaluation qualifies), so
 * there is NO connection drop and NO `Stopped` edge -- only a -32603 where
 * an answer should have been. Reading that as "the peer answered" would
 * leave no mark, and the restart the user then reaches for would re-render
 * the pick straight back into the same overflow: Q17's loop, by another
 * door. So it marks. The cost when a handler merely threw is one prompt.
 *
 * ABOUT -32800 IN PARTICULAR, because it is the one that is not obvious:
 * §2.5 names three producers and ALL THREE ARE THE SERVER'S OWN PREVIEW
 * QUEUE -- a render this one displaced, a cancelled one, and the shutdown
 * drain -- and the shutdown contract is explicit that it cannot hide a
 * death: `Preview.scala:764-766` says every QUEUED job that owes an answer
 * is answered -32800 while an IN-FLIGHT one "finishes and is answered
 * normally". So a -32800 is never the answer a dying render gets; a crashed
 * process sends none of them.
 *
 * A GUESS, AND NAMED AS ONE: that `vscode-languageclient` rejects the
 * requests it has pending when a connection closes with something OUTSIDE
 * that list (community reports say a `ResponseError` in its own private
 * -32099..-32096 band, and there is no documentation page for it). UNVERIFIED,
 * and the reason this predicate's default is "gone" rather than "settled":
 * if the guess is wrong in either direction the cost is a question, never a
 * silent re-render.
 */
const SETTLED_BY_PEER_CODES = [
  -32700, -32600, -32601, -32602,
  -32002, -32001,
  -32800, -32801, -32802, -32803,
];

function rejectionCode(err) {
  if (!err || typeof err !== "object") return undefined;
  if (typeof err.code === "number") return err.code;
  if (err.data && typeof err.data.code === "number") return err.data.code;
  return undefined;
}

function rejectionMeansServerGone(err) {
  const code = rejectionCode(err);
  if (code === undefined) return true;          // a bare Error, a string, nothing at all
  return SETTLED_BY_PEER_CODES.indexOf(code) < 0;
}

/**
 * N2 (WP-22 review). WHICH PICK DOES A WEDGE EVENT NAME?
 *
 * A stuck ANSWER or a stuck NOTIFICATION arrives while the user may
 * already have picked something else -- the default watchdog gives them a
 * whole minute -- and marking whatever is current then lands the mark on
 * an innocent report. The render that is IN FLIGHT is the better claim,
 * and the current pick is the fallback for a notification that arrives
 * with nothing running.
 *
 * IT IS STILL A PROXY, and the honest limit belongs here rather than in a
 * ticket: once the preview is stuck the server refuses EVERY later render
 * the same way (§2.5), so a `stuck: true` answer says "the preview is
 * wedged", not "THIS report wedged it". The mark can therefore name a
 * report that was merely refused. It errs towards ASKING, which is the
 * direction that cannot reopen the loop.
 */
function markPickFor(inFlightPick, currentPick) {
  return inFlightPick || currentPick;
}

/**
 * M2 (WP-22 review). The held question has no deadline: the user may answer
 * it after picking another report, and consent given for one report must
 * not be spent on another.
 *
 * `askedKey` is `markKey(pick)` as it was when the question was SHOWN.
 * Only the exact string "Render anyway" consents; a dismissal (`undefined`)
 * and "Not now" are the same answer.
 */
function promptAnswerApplies(askedKey, pickNow, markNow, choice) {
  if (choice !== "Render anyway") {
    return { render: false, why: choice === undefined ? "the question was dismissed" : String(choice) };
  }
  if (askedKey === null || askedKey === undefined || markKey(pickNow) !== askedKey) {
    return { render: false, why: "the pick changed while the question was open" };
  }
  if (!markMatches(markNow, pickNow)) {
    // Cleared underneath the question -- a save, an `invalidated`, a
    // recovery. The user still asked for this render, so it happens.
    return { render: true, why: "the mark was already cleared" };
  }
  return { render: true, why: null };
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
 * THE PRECEDENCE MATTERS AND IS TESTED (review IM-3, and WP-22 for `held`):
 *
 *     offline > stuck > held > rendering > idle
 *
 * **not running beats stuck**: §2.5 measured that a wedged server exits about
 * two minutes after the watchdog fires, so "stuck" and "the process is gone"
 * is a state the user really reaches -- and "preview: stuck" would then be
 * advice to press a Restart button on a server that is already restarting, or
 * permanently wrong if the restart failed.
 *
 * **stuck beats held**: `stuck` is now, and `held` is about the last time.
 * A fresh server that has just wedged again is what the user has to act on.
 *
 * **held beats rendering**: a held pick is not being rendered, so the two
 * cannot both be true of the same pick -- but a render of a DIFFERENT pick
 * can be in flight, and the mark still names something the user must decide
 * about. `held` is a question; `rendering` is only progress.
 *
 * `mark` is WP-22's wedge mark (or null) and is consulted the same way
 * everywhere else: a mark that is not the current pick's is not held.
 */
function statusBarState(view) {
  const v = view || {};
  const label = pickLabel(v.pick);
  const held = markMatches(v.mark, v.pick);
  if (!v.pick && !v.stuck && !held && v.running !== false) return { hidden: true };
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
  if (held) {
    return {
      hidden: false,
      text: "$(warning) Ermine preview: held",
      tooltip:
        label + " " + heldPhrase(v.mark.reason) + ".\n" +
        "Nothing has changed since, so the restart did not re-render it.\n" +
        'Render it anyway with "Ermine: Render Report to JSON", or save the file you fixed.',
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
  stuckEventApplies,
  markKey,
  markMatches,
  isMark,
  guardReduce,
  shouldAutoRender,
  heldMessage,
  rootsFingerprint,
  paramsFingerprint,
  rejectionMeansServerGone,
  markPickFor,
  promptAnswerApplies,
  SETTLED_BY_PEER_CODES,
  MARK_SEPARATOR,
  TRIGGER_RESTART,
  WEDGE_WATCHDOG,
  WEDGE_DIED_MID_RENDER,
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
