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
// WP-22 (c): OUR OWN restart, and the reason a mark carries only when no
// truer one exists. The restart we cause takes the same Stopped -> Running
// path a crash takes, so it lands on the consultation below and ASKS; this
// reason is what makes that true even in the case where nothing else had
// marked the pick. It is never written over an existing reason -- "watchdog"
// and "died-mid-render" say what happened, and "killed-by-us" only says what
// we did about it.
const WEDGE_KILLED_BY_US = "killed-by-us";
const WEDGE_REASONS = [WEDGE_WATCHDOG, WEDGE_DIED_MID_RENDER, WEDGE_KILLED_BY_US];

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
 *   killedByUs    WP-22 (c)'s grace expired and we are about    -> "killed-by-us"
 *                 to restart the server ourselves
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

    case "killedByUs":
      // WP-22 (c). THE RESTART WE ARE ABOUT TO CAUSE MUST LAND ON THIS MARK
      // -- that is the whole reason the glue sends this event BEFORE it
      // calls `restart(context)`. SET is idempotent per key, so a pick that
      // is already marked keeps its own reason and its own `at`: this row
      // only covers the case where nothing else got there first.
      return set(WEDGE_KILLED_BY_US);

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
      if (!saved) {
        // F4 OF THE WP-22(c) REVIEW, and it is N3's own rule applied to the
        // branch that was missed: a value that is PRESENT but is not a mark
        // -- most concretely, one written by a NEWER extension whose reason
        // vocabulary this one does not know -- must be CLEARED, so that
        // `applyGuard` removes the stale `workspaceState` key instead of
        // re-discarding it on every activation for ever. NOTHING stored is
        // not a clear: it is the ordinary case and must stay silent.
        const stored = event.mark !== undefined && event.mark !== null;
        return stored
          ? { mark: null, effects: guardEffects({ cleared: true, why: "the remembered mark is not one this version understands" }) }
          : { mark: null, effects: guardEffects({}) };
      }
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

/**
 * `weRestarted` (review N2) BEATS THE REASON, because the reason is usually
 * `watchdog` even when WP-22(c) restarted the server: the accepted rising
 * edge that ARMS the grace is the same event that MARKS the pick, and
 * `killed-by-us` never overwrites a mark that already exists. Telling the
 * user "the server did not come back" after we brought it back is simply
 * false, and the truthful sentence was the one almost nobody would see.
 */
function heldPhrase(reason, weRestarted) {
  if (weRestarted === true || reason === WEDGE_KILLED_BY_US) {
    return "wedged the preview, and the language server was restarted to clear it";
  }
  if (reason === WEDGE_DIED_MID_RENDER) return "was still rendering when the language server stopped";
  return "wedged the preview: the watchdog fired and the server did not come back";
}

/**
 * The text of the one non-modal warning, and `null` when there is nothing
 * to ask about -- a mark that is not this pick's is never consulted and
 * never spoken about.
 */
function heldMessage(mark, pick, weRestarted) {
  if (!markMatches(mark, pick)) return null;
  return (
    "Ermine: " + pickLabel(pick) + " " + heldPhrase(mark.reason, weRestarted) +
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

// -------------------------------------------- WP-22 (c): the restart timer
//
// THE USER'S DECISION, in four words: "the extension may restart." The
// wedge is contained in the CALLER ("responsiblity for solving this happens
// with the *caller*"), so when the preview has been stuck for long enough
// the EXTENSION restarts its own language server through the path it
// already has (`restart(context)` -> `stopQuietly` -> `startClient`).
//
// WHY THERE IS A TIMER AT ALL, rather than a restart on `{stuck:true}`:
// Q10's recovery. The watchdog answers a render after
// `ermine.preview.timeoutSeconds` (default 60) and marks the preview stuck,
// and the job may STILL come back -- a 300 s scan under a 60 s watchdog is
// slow, not wedged -- at which point the server sends `{stuck:false}` and
// everything is fine. Killing on the rising edge would kill that render
// every time. So: arm a grace on the rising edge, disarm it on the falling
// one. THE GRACE IS POLICY AND THE EXTENSION IS WHERE POLICY BELONGS; the
// server is not changed by any of this and knows nothing about it (Q18: it
// keeps no self-defence, and `bin/ermine-serve` and every non-VS-Code
// client are unprotected).
//
// WHAT THIS REDUCER IS AND IS NOT. It owns the timer's LIFECYCLE and holds
// NO CLOCK: the glue owns `setTimeout` and hands the expiry back as an
// event carrying the SERIAL of the arm it belongs to. Every arm mints a new
// serial, so a timer armed for an earlier incident -- one the glue failed
// to cancel, or one that had already been queued when the disarm ran --
// cannot fire: its serial is not the live one. (The watchdog's own
// arm-epoch idea, `Preview.scala`, in eleven lines of JavaScript.)
//
// THE MIRROR, AND WHY IT IS NOT A SECOND TRUTH. The fire condition is
// "still stuck, still Running", so this reducer tracks those two flags --
// by EXACTLY `stuckReduce`'s rules, over the SAME events, with the SAME
// `applies` discipline the guard uses (a stale notification must not arm
// anything). It does not re-derive the acceptance: the glue computes
// `stuckEventApplies` ONCE and hands the answer to both reducers. A
// property pins the mirror against `stuckReduce` event for event, exactly
// as stage 1 pins `stuckEventApplies` against it.
//
// THE PICK IS NOT PART OF THIS. A pick change does NOT disarm, and the
// argument is the one the ticket's own §2.5 makes: THE WEDGE IS THE
// SERVER'S STATE, NOT THE PICK'S. Once the preview is stuck the server
// refuses EVERY later render the same way, for every pick, and
// `ermine/preview/stuck` is per PROCESS (its `seq` restarts at 1 in a fresh
// one). Picking another report changes which report is refused and nothing
// else. Disarming there would also be the worst kind of silent failure:
// §4's rule (5) was WITHDRAWN, so there is ONE rising edge per incident --
// a disarm with no way back would leave the server wedged for the rest of
// the session precisely when the user is trying to work around it. What IS
// pick-scoped is the guard's MARK, and it stays pick-scoped: a pick change
// clears it, the new pick's own refusal marks it again, and the glue
// refuses to fire at all if it cannot attribute the wedge to a pick.
//
// THE HARD FLOOR. `RESTART_FLOOR_MS` is a last-resort rate limit: whatever
// the setting says and whatever state anything else gets into, two
// restarts cannot happen closer together than this. It is not the design's
// bound -- the guard is, because every restart we cause lands on a mark and
// ASKS -- it is the bound that survives a bug in the guard, in the glue or
// in the library. 30 s is chosen against three MEASURED numbers: the
// server's boot is ~14 s (`test/load-test.js`: "129 modules in 14.1s"), so
// a storm cannot run faster than about two restarts a minute even if
// everything else fails; the default watchdog is 60 s, so the floor cannot
// bite a default configuration at all; and the only configurations it can
// bite are deliberately aggressive ones (`timeoutSeconds` 5 with a grace
// under ~15 s), where the refusal is logged and the Restart Language Server
// button is still there. A clock that moves BACKWARDS refuses too (the
// difference is negative, which is below the floor) -- the safe direction.

const RESTART_GRACE_MAX = 3600;
const RESTART_FLOOR_MS = 30000;

/**
 * `ermine.preview.restartAfterStuckSeconds`, validated the way
 * `previewSettings` validates the two the server reads: nonsense is NAMED
 * rather than guessed at, and the outcome is stated.
 *
 * NONSENSE FALLS BACK TO 0 = OFF, not to some default grace: a value nobody
 * can parse must not start killing servers. A value ABOVE the maximum is
 * CLAMPED rather than dropped, because the intent (restart eventually) is
 * unambiguous and a grace over an hour is indistinguishable from one.
 *
 * THE MAXIMUM IS ALSO LOAD-BEARING, not decoration: the glue turns these
 * seconds into `setTimeout(..., seconds * 1000)`, and a delay over 2^31-1
 * ms does not wait -- Node's documented behaviour is to run the timeout
 * IMMEDIATELY. An unclamped `1e9` would therefore restart the server at
 * once, which is the exact opposite of what it asks for. 3600 s is four
 * orders of magnitude clear of that.
 */
function restartGraceSetting(raw) {
  const name = "ermine.preview.restartAfterStuckSeconds";
  const problems = [];
  if (raw === undefined || raw === null || raw === "") return { seconds: 0, problems };
  if (typeof raw !== "number" || !isFinite(raw)) {
    problems.push(
      name + " is a whole number of seconds, not a " + typeName(raw) +
      " (" + printable(raw) + "); the automatic restart stays OFF"
    );
    return { seconds: 0, problems };
  }
  if (Math.floor(raw) !== raw) {
    problems.push(name + " of " + raw + " is not a whole number of seconds; the automatic restart stays OFF");
    return { seconds: 0, problems };
  }
  if (raw < 0) {
    problems.push(name + " of " + raw + " is not a length of time; the automatic restart stays OFF");
    return { seconds: 0, problems };
  }
  if (raw > RESTART_GRACE_MAX) {
    problems.push(
      name + " of " + raw + " is above the maximum of " + RESTART_GRACE_MAX +
      " seconds (one hour) and was clamped to it"
    );
    return { seconds: RESTART_GRACE_MAX, problems };
  }
  return { seconds: raw, problems };
}

/**
 * `seconds` is the validated setting; `armed` is the SERIAL of the live arm
 * or null; `serial` is the last serial minted; `stuck` and `running` are the
 * mirror; `lastFireAt` is the clock value the glue passed with the last
 * fire, and the floor's only memory. It outlives our own restarts on
 * purpose -- the extension host is not reloaded by them.
 */
function initialRestartState(seconds) {
  return {
    // N6: the clamp lives here and in the `setting` case as well as in
    // `restartGraceSetting`, so the number the reducer STORES can never be
    // one `setTimeout` would run immediately, whoever hands it over.
    seconds: clampGrace(seconds),
    armed: null,
    // The seconds THIS arm was made for, which is not always the setting:
    // an arm inside the floor waits for the floor instead (review D2), and
    // the user is shown this number rather than the setting.
    armedFor: 0,
    serial: 0,
    stuck: false,
    running: true,
    lastFireAt: null,
    // D3: only a restart that actually STARTED sets `lastFireAt`, and a
    // refusal is remembered so that something other than the output channel
    // can say so.
    lastRefusal: null,
    // N2 AND DELTA REVIEW (d): A ONE-SHOT TOKEN, NOT A MOOD. `restartPending`
    // is minted by `fired` and CONSUMED by the single Stopped -> Running
    // that restart causes, which turns it into `restartedByUs` for exactly
    // that edge -- the edge the held question is asked on. Before this it
    // survived for ever, so a SPONTANEOUS death ten minutes later was
    // described to the user as "the language server was restarted to clear
    // it", which we had not done.
    restartPending: false,
    restartedByUs: false,
  };
}

function clampGrace(seconds) {
  if (typeof seconds !== "number" || !isFinite(seconds) || seconds <= 0) return 0;
  return Math.min(Math.floor(seconds), RESTART_GRACE_MAX);
}

const NO_RESTART_EFFECTS = {
  arm: false, disarm: false, fire: false, refused: false,
  // Not a state: a defect in the CALLER, which the glue logs as a BUG line.
  bug: null,
  // `seconds` is what the USER is told; `ms` is what the glue gives
  // `setTimeout`. They differ only when the floor stretched the arm.
  seconds: 0, ms: 0, serial: 0, why: null,
};

function restartEffects(over) {
  return Object.assign({}, NO_RESTART_EFFECTS, over);
}

/**
 * EVERY EVENT THIS REDUCER TAKES IS BUILT HERE, AND THE CLOCK IS AN
 * ARGUMENT (delta review M1).
 *
 * THE BUG THIS EXISTS TO MAKE IMPOSSIBLE: the arm-time floor stretch --
 * review D2's whole point, that the number on the notification is the
 * number the restart will actually happen at -- reads `event.at`, and the
 * three events that can ARM were sent from `extension.js` as bare object
 * literals WITHOUT a clock. So the stretch never ran in the shipped
 * extension, the announced number was the raw setting, and the expiry-time
 * backstop -- documented as "normally unreachable" -- was the only path
 * that ever ran. The outcome stayed correct (the floor still held); the
 * SENTENCE THE USER READ did not. `runGlue` in the test file supplied `at`
 * on exactly the events the glue omitted it from, so no test could see it.
 *
 * SO: `extension.js` constructs NO reducer event of its own, the test
 * model calls THESE SAME BUILDERS, and a builder that is handed no clock
 * where a clock decides something produces `at: null`, which `arm()`
 * reports as a BUG rather than silently treating as zero.
 */
const restartEvents = {
  /** `ermine/preview/stuck`, with rule (1)/(3)'s acceptance already computed. */
  notification: (stuck, applies, at) => ({
    type: "notification", stuck: stuck === true, applies: applies !== false, at: clockOf(at),
  }),
  /** The `stuck` marker on a render's own answer. */
  answer: (stuck, applies, at) => ({
    type: "answer", stuck: stuck === true, applies: applies !== false, at: clockOf(at),
  }),
  /** Any transition the language client reports. */
  clientState: (to) => ({ type: "clientState", to }),
  /** `ermine.preview.restartAfterStuckSeconds` changed (or was read at activation). */
  setting: (seconds, at) => ({ type: "setting", seconds, at: clockOf(at) }),
  /** The one timer went off, carrying the serial of the arm it belongs to. */
  expiry: (serial, at) => ({ type: "expiry", serial, at: clockOf(at) }),
  /** `restart(context)` was actually started. */
  fired: (at) => ({ type: "fired", at: clockOf(at) }),
  /** `fireRestart` refused, and why. */
  fireRefused: (why, at) => ({ type: "fireRefused", why, at: clockOf(at) }),
  /** The window is going away. */
  deactivate: () => ({ type: "deactivate" }),
};

function clockOf(at) {
  return typeof at === "number" && isFinite(at) ? at : null;
}

/**
 * THE WHOLE EVENT TABLE, and every row of it is a test.
 *
 * ARM  (one grace per incident, a new serial each time; the delay is
 *       `max(the setting, what is left of the floor)`, so the number the
 *       user is shown is the one the restart will actually happen at)
 *   notification `{stuck:true, applies}`  on the RISING edge, while Running
 *                                         and `seconds > 0`
 *   answer       `{stuck:true, applies}`  same, for the wedged answer -- it
 *                                         arrives BEFORE the notification
 *                                         (MEASURED over the wire) and the
 *                                         two are one incident, so the
 *                                         second of them re-arms nothing
 *   setting      a CHANGE to another non-zero value WHILE ARMED: re-armed
 *                at the new value, from now
 *   setting      a CHANGE from 0 to non-zero WHILE THE PREVIEW IS STUCK and
 *                the client is Running: armed there and then (review D1)
 *   expiry       inside the floor: RE-ARMED for what is left of it (review
 *                D2), never disarmed -- an incident must not be stranded
 * DISARM
 *   notification `{stuck:false, applies}` Q10's recovery -- LOAD-BEARING:
 *                                         without it a slow-but-finite
 *                                         render is killed for being slow
 *   clientState  Stopped                  the server died by itself
 *   clientState  Starting                 the client left Running
 *   clientState  Running                  a fresh process; `stuckReduce`
 *                                         resets, so there is nothing stuck
 *   setting      a change to 0            the user turned it off
 *   deactivate   the window is going away
 * FIRE (the glue then marks the pick and calls `restart(context)`, and
 *       REPORTS BACK -- `fired` or `fireRefused` -- because only a restart
 *       that actually started may consume the floor, review D3)
 *   expiry       serial === armed, still stuck, still Running, `seconds > 0`,
 *                and the floor has passed
 * AFTER THE FIRE (the glue's answer)
 *   fired        the restart was started: `lastFireAt` is set HERE and
 *                nowhere else, and `restartedByUs` goes true so the held
 *                question can say who restarted the server
 *   fireRefused  `fireRestart` refused (no pick to attribute the wedge to,
 *                no extension context, the mark did not take, or a restart
 *                was already under way): the floor's memory is UNTOUCHED
 *                and the reason is kept for the status bar, because a
 *                refusal that only reaches the output channel leaves a
 *                wedged server and a user who is told nothing
 * NOTHING AT ALL
 *   expiry       a serial that is not the live arm's -- A STALE TIMER, and
 *                the live arm SURVIVES it
 *   expiry       no live arm
 *   expiry       carrying no clock (the floor must not be unfalsifiable)
 *   anything     the event was not accepted (`applies === false`)
 *   setting      the same value again -- VS Code fires a configuration
 *                event for every `ermine.*` key, and re-arming on each of
 *                them would extend a grace for as long as the user keeps
 *                typing in settings.json
 *
 * TURNING THE SETTING ON MID-INCIDENT ARMS (review D1, and the first build
 * had this the other way round). Reaching for the setting BECAUSE the
 * preview is wedged is the likeliest moment anyone touches it, and §4's
 * rule (5) withdrawal means there is no second rising edge to save them --
 * the first build stranded exactly that user. The old justification ("it
 * keeps 'armed implies a rising edge' true, which is what makes the serial
 * mean something") did not hold: the reducer already re-arms on a setting
 * change while armed, and EVERY arm mints a fresh serial unconditionally,
 * so nothing about the serial depended on it. The guard still bounds every
 * restart that follows.
 *
 * THE FLOOR NEVER STRANDS AN INCIDENT (review D2). It is applied TWICE and
 * in neither place does it disarm: at ARM time the delay is stretched to
 * `lastFireAt + RESTART_FLOOR_MS`, so the notification the user reads names
 * the real number rather than one the floor is about to refuse; and at
 * EXPIRY -- reachable when the arm carried no clock, or the system clock
 * moved -- the timer is RE-ARMED for what is left, with a new serial.
 */
function restartReduce(state, event) {
  const s = state || initialRestartState(0);
  const keep = { state: s, effects: restartEffects({}) };
  if (!event || typeof event !== "object") return keep;

  let seconds = s.seconds;
  let armed = s.armed;
  let armedFor = s.armedFor;
  let serial = s.serial;
  let stuck = s.stuck;
  let running = s.running;
  let lastFireAt = s.lastFireAt;
  let lastRefusal = s.lastRefusal;
  let restartPending = s.restartPending;
  let restartedByUs = s.restartedByUs;
  let fx = {};

  // The clock the glue passed with THIS event, or null. The reducer never
  // reads a clock of its own; it only compares numbers it was handed.
  const at = typeof event.at === "number" && isFinite(event.at) ? event.at : null;

  const disarm = (why) => {
    if (armed === null) return;
    armed = null;
    armedFor = 0;
    fx = { disarm: true, why };
  };
  // A new serial EVERY time, so the timer the glue is about to set is the
  // only one that can fire. The glue clears the timer it holds before
  // setting a new one, so an `arm` effect is a disarm of the previous one
  // as well.
  //
  // THE DELAY IS THE LARGER OF THE SETTING AND WHAT IS LEFT OF THE FLOOR
  // (review D2): the floor is going to refuse an earlier fire anyway, and a
  // notification that says "in 5 s" for a restart that cannot happen for 24
  // more is a lie the user has no way to correct. With no clock on the
  // event the setting is used and the expiry-time check is the backstop.
  const arm = (why) => {
    const wanted = seconds * 1000;
    // THE CLOCK IS REQUIRED WHEN IT DECIDES SOMETHING (delta review M1). An
    // arm with a previous restart behind it has to know how much of the
    // floor is left; without a clock it cannot, and the first build quietly
    // used zero, which is how D2's stretch came to be dead code in the
    // shipped glue. It still ARMS -- refusing to arm would turn a reporting
    // defect into a broken feature, and the expiry-time backstop still
    // enforces the floor -- but it says BUG, out loud, and a test pins it.
    const clockless = at === null && lastFireAt !== null;
    const floorLeft = lastFireAt !== null && at !== null ? lastFireAt + RESTART_FLOOR_MS - at : 0;
    const ms = Math.max(wanted, floorLeft);
    serial = serial + 1;
    armed = serial;
    armedFor = Math.ceil(ms / 1000);
    lastRefusal = null;
    restartPending = false;
    restartedByUs = false;
    fx = {
      arm: true,
      seconds: armedFor,
      ms,
      serial,
      // The channel's arm line says the same thing the notification says.
      why: ms > wanted ? why + "; " + floorReason(armedFor, seconds) : why,
    };
    if (clockless) {
      fx.bug =
        "restartReduce was asked to arm with no clock on the event, so the 30 s floor could not be " +
        "taken into account and the time the user is shown may be too short; every event must be built " +
        "by core.restartEvents.*";
    }
  };
  const rise = () => {
    stuck = true;
    if (running && seconds > 0) arm("the preview is stuck and nothing has come back");
  };

  switch (event.type) {
    case "notification":
      if (event.applies === false) return keep;
      if (event.stuck === true) {
        if (stuck) return keep;                 // one rising edge per incident
        rise();
        break;
      }
      stuck = false;
      // The incident is over: a refusal from it no longer describes
      // anything, and neither does "we restarted it".
      lastRefusal = null;
      restartPending = false;
      restartedByUs = false;
      disarm("the wedged render came back (ermine/preview/stuck {stuck:false})");
      break;

    case "answer":
      // Rule (3): the marker on an ANSWER is per-request, and `applies` is
      // the same predicate the banner and the guard use.
      if (event.applies === false || event.stuck !== true) return keep;
      if (stuck) return keep;
      rise();
      break;

    case "clientState":
      if (event.to === "Running") {
        stuck = false;
        running = true;
        // THE TOKEN IS CONSUMED HERE (delta review (d)): this edge, and no
        // later one, is the one our restart caused, and it is the edge the
        // held question is asked on -- so `restartedByUs` is true for it
        // and false for every Running after it.
        restartedByUs = restartPending;
        restartPending = false;
        lastRefusal = null;
        disarm("the language server is running again");
        break;
      }
      if (event.to === "Stopped") {
        running = false;
        disarm("the language server stopped");
        break;
      }
      // `Starting`: `stuckReduce` moves nothing here and neither does the
      // mirror, but the client has left Running, so a grace armed for the
      // process that is going away is dropped.
      disarm("the language client left Running");
      break;

    case "setting": {
      const next = clampGrace(event.seconds);
      if (next === seconds) return keep;
      seconds = next;
      if (seconds === 0) {
        disarm("ermine.preview.restartAfterStuckSeconds was set to 0");
        break;
      }
      // D1: armed -> re-armed at the new value; NOT armed but the preview
      // is stuck right now -> armed here, because that is the moment anyone
      // reaches for this setting and there will be no second rising edge.
      if (armed !== null) arm("ermine.preview.restartAfterStuckSeconds changed to " + seconds + " s");
      else if (stuck && running) arm("ermine.preview.restartAfterStuckSeconds was turned on while the preview was stuck");
      break;
    }

    case "expiry": {
      // A STALE TIMER CAN NEVER FIRE, and it must not disarm the live one
      // either: the state is returned untouched.
      if (armed === null) {
        return { state: s, effects: restartEffects({ why: "the grace had already been disarmed" }) };
      }
      if (event.serial !== armed) {
        return {
          state: s,
          effects: restartEffects({
            why: "a timer armed for an earlier incident fired (serial " + String(event.serial) + ", live " + String(armed) + ")",
          }),
        };
      }
      // Defence in depth: every one of these should already have disarmed.
      if (!stuck) {
        disarm("the preview is no longer stuck");
        break;
      }
      if (!running) {
        disarm("the language server is not running");
        break;
      }
      if (!(seconds > 0)) {
        disarm("ermine.preview.restartAfterStuckSeconds is 0");
        break;
      }
      if (at === null) {
        disarm("the expiry carried no clock, so the floor could not be checked");
        break;
      }
      // D2: INSIDE THE FLOOR, RE-ARM FOR WHAT IS LEFT OF IT -- never
      // disarm. A disarm here stranded the incident for the rest of the
      // session, because §4's rule (5) withdrawal means no second rising
      // edge comes to re-arm it. Normally unreachable now that the arm
      // stretches itself; a clock that moved, or an arm that carried none,
      // still gets here.
      if (lastFireAt !== null && at - lastFireAt < RESTART_FLOOR_MS) {
        const left = Math.max(1, lastFireAt + RESTART_FLOOR_MS - at);
        serial = serial + 1;
        armed = serial;
        armedFor = Math.ceil(left / 1000);
        fx = {
          arm: true,
          seconds: armedFor,
          ms: left,
          serial,
          why:
            "the last restart was " + Math.round((at - lastFireAt) / 1000) +
            " s ago and no two may be closer than " + Math.round(RESTART_FLOOR_MS / 1000) +
            " s, so the restart waits another " + armedFor + " s",
        };
        break;
      }
      armed = null;
      armedFor = 0;
      // D3: `lastFireAt` is NOT set here. The glue may still refuse this
      // fire (nothing to attribute the wedge to, no context, the mark did
      // not take, a restart already under way), and a refusal must not make
      // the floor block a later legitimate restart. It is set by the
      // `fired` event the glue sends back.
      fx = {
        fire: true,
        seconds,
        ms: 0,
        serial: event.serial,
        why: "the preview has been stuck for " + seconds + " s",
      };
      break;
    }

    // D3: THE GLUE'S ANSWER TO A FIRE. `restart(context)` was actually
    // started, so the floor's memory moves and the held question the
    // restart is about to raise can say who restarted the server (N2).
    case "fired":
      lastFireAt = at !== null ? at : lastFireAt;
      lastRefusal = null;
      // Minted, not spent: the Stopped -> Running this restart causes is
      // what turns it into `restartedByUs`, once.
      restartPending = true;
      break;

    // D3: the fire was REFUSED by the glue. The floor's memory is untouched
    // -- nothing was restarted -- and the reason is kept so the status bar
    // can say the preview is stuck AND that the automatic restart did not
    // happen. A refusal that only reaches the output channel leaves a
    // wedged server and a user who is told nothing.
    case "fireRefused":
      lastRefusal = typeof event.why === "string" && event.why ? event.why : "the automatic restart did not happen";
      fx = { refused: true, why: lastRefusal };
      break;

    case "deactivate":
      disarm("the extension is shutting down");
      break;

    default:
      return keep;
  }

  return {
    state: {
      seconds, armed, armedFor, serial, stuck, running,
      lastFireAt, lastRefusal, restartPending, restartedByUs,
    },
    effects: restartEffects(fx),
  };
}

/**
 * How many seconds the armed grace has, or 0 when nothing is armed.
 *
 * It is `armedFor`, NOT the setting: an arm made inside the floor waits for
 * the floor instead, and the number the user is shown has to be the one the
 * restart will actually happen at (review D2).
 */
function restartArmedSeconds(state) {
  const s = state || initialRestartState(0);
  return s.armed === null ? 0 : s.armedFor;
}

/**
 * F1 OF THE WP-22(c) REVIEW. WHO MAY RESTART, AND WHEN.
 *
 * Stage 2's first build took a plain `restartInFlight` latch around
 * `restart(context)`, and the reviewer found the one way stage 2 could make
 * an EXISTING feature worse: `stopQuietly` awaits `client.stop()` with no
 * bound and catches only a THROW, so a `stop()` that never settles left the
 * latch true for the life of the window -- and then **Ermine: Restart
 * Language Server**, the command AND the button on our own stuck
 * notification, returned early for ever. In exactly the situation the
 * button exists for.
 *
 * TWO CHANGES, and this is the pure half:
 *
 *  1. **THE USER ALWAYS WINS.** A restart asked for by a person is never
 *     refused. It SUPERSEDES one that is already under way -- the glue
 *     mints a new epoch, and the older run abandons at its next checkpoint
 *     rather than starting a second client beside the new one.
 *  2. **THE TIMER NEVER STACKS.** An automatic restart is refused while any
 *     restart is under way, and the refusal is reported back to
 *     `restartReduce` as `fireRefused`, so the floor is not consumed by a
 *     restart that never started (D3).
 *
 * The other half is the glue's, and cannot be pure: `stopQuietly` now
 * bounds its wait, so the latch is time-limited even without this.
 */
const RESTART_BY_USER = "user";
const RESTART_BY_TIMER = "timer";

function restartAttempt(underway, source) {
  const who = source === RESTART_BY_TIMER ? RESTART_BY_TIMER : RESTART_BY_USER;
  if (!underway) return { proceed: true, supersedes: false, why: null };
  const running = underway.source === RESTART_BY_TIMER ? "an automatic restart" : "a restart";
  if (who === RESTART_BY_TIMER) {
    return { proceed: false, supersedes: false, why: running + " is already under way" };
  }
  return { proceed: true, supersedes: true, why: "the user asked while " + running + " was under way, so it takes over" };
}

/** The reason the last automatic restart did NOT happen, or null (D3). */
function restartProblem(state) {
  const s = state || initialRestartState(0);
  return s.armed === null && typeof s.lastRefusal === "string" ? s.lastRefusal : null;
}

/** Did WE restart the server for the incident that is still open? (N2) */
function restartedByUs(state) {
  return !!(state && state.restartedByUs);
}

/**
 * What the user is told while the grace runs, and how to stop it.
 *
 * IT SAYS THE MANUAL RESTART IS OPTIONAL (review N1). The server's own
 * stuck message ends by telling the user to run **Ermine: Restart Language
 * Server**, and appending "it will be restarted automatically" to that
 * without a word between them told them to do it by hand and that they need
 * not, in one breath.
 */
function floorReason(armedFor, asked) {
  return (
    "not before " + armedFor + " s, because the language server was restarted less than " +
    Math.round(RESTART_FLOOR_MS / 1000) + " s ago and restarts are limited to one every " +
    Math.round(RESTART_FLOOR_MS / 1000) + " s (you asked for " + asked + " s)"
  );
}

function restartNotice(seconds, asked) {
  if (typeof seconds !== "number" || !(seconds > 0)) return null;
  // DELTA REVIEW: a user who set 5 and is told 25 has to be told WHY, or
  // the number looks like a bug in the setting they just typed.
  const stretched = typeof asked === "number" && asked > 0 && seconds > asked
    ? " It is " + floorReason(seconds, asked) + "."
    : "";
  return (
    "You do not need to do that by hand: the language server will be restarted automatically in " +
    seconds + " s unless the render comes back." + stretched +
    " Set ermine.preview.restartAfterStuckSeconds to 0 to stop that."
  );
}

/**
 * The stuck notification's text, with the grace on it when one is armed.
 *
 * THE JOIN IS PUNCTUATED (review N1): the server's message ends
 * `... (ermine.restartServer)` with no terminator, and a bare space made
 * one run-on sentence out of two.
 */
function stuckNotificationText(message, armedSeconds, asked) {
  const text = String(message || "the preview is stuck").trim();
  const notice = restartNotice(armedSeconds, asked);
  if (!notice) return "Ermine: " + text;
  return "Ermine: " + (/[.!?]$/.test(text) ? text : text + ".") + " " + notice;
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
    // WP-22 (c): while the grace runs the tooltip says so, and says how to
    // stop it. `restartIn` is 0 whenever nothing is armed -- which is
    // always, with the setting at its default of 0.
    const notice = restartNotice(v.restartIn, v.restartAsked);
    // D3: a refusal is not a log line. If the automatic restart was asked
    // for and did not happen, the thing the user is looking at says so.
    const problem = typeof v.restartProblem === "string" && v.restartProblem
      ? "The automatic restart did not happen: " + v.restartProblem + "."
      : null;
    const extra = notice || problem;
    return {
      hidden: false,
      text: "$(warning) Ermine preview: stuck",
      tooltip: (v.message || "the preview is stuck") + (extra ? "\n" + extra : ""),
      severity: "warning",
    };
  }
  if (held) {
    return {
      hidden: false,
      text: "$(warning) Ermine preview: held",
      tooltip:
        label + " " + heldPhrase(v.mark.reason, v.restartedByUs) + ".\n" +
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
  WEDGE_KILLED_BY_US,
  restartGraceSetting,
  initialRestartState,
  restartReduce,
  restartArmedSeconds,
  restartProblem,
  restartedByUs,
  restartAttempt,
  restartEvents,
  RESTART_BY_USER,
  RESTART_BY_TIMER,
  restartNotice,
  stuckNotificationText,
  RESTART_GRACE_MAX,
  RESTART_FLOOR_MS,
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
