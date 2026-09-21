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

// ------------------------------------------------- params files (WP-8, S1)

// WHAT THIS SECTION IS, AND WHAT IT DELIBERATELY IS NOT.
//
// Section 6 of tracker/JSON-WIDGET-PLAYGROUND.md makes a report's parameters
// an ordinary committed file, `.ermine/preview/<Module>/<binding>.params.json`,
// with a generated `<binding>.schema.json` beside it so the JSON editor can
// complete keys and squiggle wrong ones.  That is three jobs -- WHERE the
// files go, WHAT a first skeleton holds, and WHAT is actually sent -- and all
// three are decisions, so all three are here and none of them touches a disk.
//
// S1 IS PURE.  Nothing below reads, writes, watches or creates a file, and
// nothing below is wired into `src/extension.js` yet: the writes, the watcher
// and the `ermine/schema` client are S2 and S3.  Everything here is a
// function from plain data to plain data, and `test/preview-core.test.js`
// holds a table row for every case and four properties over generated input.
//
// THE THREE RULES THE WHOLE SECTION IS BUILT ON:
//
//  1. NEVER WRITE OUTSIDE A WORKSPACE FOLDER (review G1).  A report opened
//     from `/tmp` has no business minting `.ermine/` in an unrelated repo, so
//     `paramsPaths` REFUSES rather than guessing, and the caller falls back to
//     the inline `{}` WP-7 already sends and says so once.
//  2. THE SKELETON IS THE SMALLEST VALUE THAT DECODES.  Required keys get a
//     value, optional (`Maybe`) keys are left out entirely -- `docs/JSON-GUIDE.md`
//     is explicit that a `Maybe` field must be OMITTED and that `null` in its
//     place is a 400 -- lists start empty, and a `Maybe` position takes the
//     shortest alternative that decodes.  A skeleton the developer has to
//     delete from is worse than one they have to fill in.
//  3. A FILE IS NOT A SECRET STORE (section 8, A1/A5/A6/A9).  A params file is
//     committed AND its value is spliced into the render body that goes to
//     `ERMINE_LSP_LOG`, so a password in one is a password in the repository
//     and in the log.  U5 decided the shape of the answer: WARN, once, never
//     block -- a report may legitimately take a `token` parameter, and a
//     refusal the developer cannot override is a feature that gets turned off.

/**
 * `paramsPaths`, `skeletonFrom` and `paramsToSend` all answer `{problem}`
 * rather than throwing, and a problem is a NAMED REASON plus a sentence a
 * human reads.  The reason is what the glue switches on (a fallback, a log
 * line, a notification); the sentence is what it shows.  Neither is derived
 * from the other, because a message that has to be re-parsed to be acted on
 * is the bug `absoluteRoots`'s `problems` list already avoids.
 */
function problem(reason, message) {
  return { problem: { reason: String(reason), message: String(message) } };
}

// -- where the files go ----------------------------------------------------

/** `.ermine/preview` -- the two segments every generated path starts with. */
const PREVIEW_SEGMENTS = [".ermine", "preview"];

/**
 * A NAME THIS CODE MINTS IS AN ERMINE IDENTIFIER OR IT IS NOT A FILE NAME.
 *
 * The picker takes free text for a binding (`extension.js`'s "Type a binding
 * name..."), so `<+>` and `../../etc/passwd` both reach here.  Rather than
 * enumerate what is illegal on some filesystem -- a list that is wrong on the
 * next one -- the rule is a WHITELIST: a letter or `_`, then letters, digits,
 * `_` and `'`.  That refuses, in one test, every case review G3 lists (an
 * operator binding, `/`, `\`, `:`, a NUL byte, a leading dot, a trailing dot
 * or space, the empty string) plus `..` and an absolute path, and it refuses
 * them the same way on Linux and on Windows.
 *
 * IT IS NOT "AN ERMINE IDENTIFIER", AND THE COMMENT THAT SAID SO WAS WRONG
 * (the S1 review's nits 1-3).  Against `scalaparsers/ParsingUtil.scala` it is
 * both narrower and wider, and each departure is deliberate:
 *   NARROWER -- `#` is a legal tail character (`tailChar`, `:351`), so
 *     `report#` is a legal binding and gets NO params file.  Kept out on
 *     purpose: the path becomes part of a `file:` URI in the editor, where
 *     `#` opens a fragment and has to be percent-encoded, and nobody has run
 *     VS Code on this branch to see whether that round-trips.  By convention
 *     `#` marks a native (`List#`, `mkRelationWithHeader#`), which is not a
 *     report, so the cost is small and it is named when it is paid;
 *   NARROWER -- `letter` is `satisfy(_.isLetter)` (`:121`), so `Métier` and
 *     `rapporté` are legal Ermine and get no params file either.  A
 *     non-ASCII component is exactly where a Windows code page, a
 *     case-folding rule and a `git` `core.precomposeunicode` setting
 *     disagree, and all three are unobserved here;
 *   WIDER -- a leading `_` and a lowercase module start are accepted and
 *     cannot occur in Ermine (`identStart = letter`; `upper >> identTail`,
 *     `SurfaceParsers.scala`).  Over-accepting a name that cannot exist
 *     costs nothing.
 * IN EVERY REFUSED CASE THE REPORT STILL RENDERS, with the inline `{}`, and
 * the refusal is named; section 6 records the limitation out loud.
 *
 * REFUSING IS CHEAP AND SAFE: there is no params FILE for such a binding, the
 * caller sends `{}` inline exactly as WP-7 does today, and the render still
 * happens.  A false refusal costs a message; a false accept writes a file
 * somewhere nobody looked.
 */
const SAFE_NAME = /^[A-Za-z_][A-Za-z0-9_']*$/;

/** A module name is dotted and is ONE directory (`Layout.Report`), never a path. */
const SAFE_MODULE = /^[A-Za-z_][A-Za-z0-9_']*(\.[A-Za-z_][A-Za-z0-9_']*)*$/;

/**
 * A name component is at most this long so that `<binding>.schema.json` (13
 * more characters) stays well inside the 255-byte component limit every
 * mainstream filesystem imposes, and so the generated tail
 * `.ermine/preview/<Module>/<binding>.params.json` still fits inside Windows'
 * 260-character MAX_PATH under a workspace folder of ordinary depth.
 */
const MAX_NAME_LENGTH = 120;

/**
 * Windows' reserved DEVICE names (review G4).  On Windows these cannot be a
 * file OR a directory whatever the extension, so `NUL.params.json` and a
 * module called `Con` are both unwritable -- and `§10` says the deployment
 * machines are Windows.  They are refused on EVERY platform, on purpose: a
 * params file is committed, so a Linux developer who gets away with `Aux`
 * hands a checkout that cannot be cloned to the colleague who cannot.
 */
const RESERVED_DEVICE_NAMES = [
  "CON", "PRN", "AUX", "NUL",
  "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
  "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/**
 * Windows reads the device name off the part BEFORE the first dot, so
 * `NUL.params.json`, `nul.txt` and `NUL` are one name, and the match is
 * case-insensitive.  A segment that begins with a dot (`.ermine`) has an
 * empty part before it and is therefore never reserved.
 */
function isReservedDeviceName(segment) {
  const base = String(segment).split(".")[0].toUpperCase();
  return RESERVED_DEVICE_NAMES.indexOf(base) >= 0;
}

/**
 * `"posix"` or `"win32"` -> the matching half of Node's `path`.
 *
 * The flavour is an ARGUMENT rather than the host's, for one reason: every
 * Windows rule in this section (the separator, the case-insensitive compare,
 * the device names) is a rule nobody here can run, and a rule that cannot be
 * tested is a rule that is wrong.  `path.win32` is available on Linux, so
 * both halves are table-tested on the machine that runs the gates.  The
 * default is the host's, which is what the glue wants.
 */
function pathFlavour(flavour) {
  if (flavour === "win32") return path.win32;
  if (flavour === "posix") return path.posix;
  if (flavour && typeof flavour === "object" && typeof flavour.join === "function") return flavour;
  return path.sep === "\\" ? path.win32 : path.posix;
}

/** Trailing separators off, `.`/`..` collapsed, and folded for a win32 compare. */
function comparablePath(p, value) {
  let normalised = p.normalize(String(value));
  while (normalised.length > 1 && normalised.endsWith(p.sep)) normalised = normalised.slice(0, -1);
  return p === path.win32 ? normalised.toLowerCase() : normalised;
}

/**
 * Is `child` strictly inside `folder`?
 *
 * A PREFIX COMPARE, NOT `path.relative`: `relative` calls `resolve`, which
 * falls back to `process.cwd()` the moment either side is not absolute, and a
 * containment test whose answer depends on where the editor was started is
 * not a containment test.  Both sides are required to be absolute for the
 * same reason.  The `+ sep` is what keeps `C:\workspace-old` out of
 * `C:\workspace`.
 */
function isInsideFolder(p, folder, child) {
  if (typeof folder !== "string" || typeof child !== "string") return false;
  if (!folder || !child) return false;
  if (!p.isAbsolute(folder) || !p.isAbsolute(child)) return false;
  const f = comparablePath(p, folder);
  const c = comparablePath(p, child);
  if (c === f) return false;
  const withSep = f.endsWith(p.sep) ? f : f + p.sep;
  return c.startsWith(withSep);
}

/**
 * WHERE THIS PICK'S PARAMS AND SCHEMA LIVE, or why they cannot live anywhere.
 *
 *   `.ermine/preview/<Module>/<binding>.params.json`
 *   `.ermine/preview/<Module>/<binding>.schema.json`
 *   `.ermine/preview/.gitignore`                       (U7, written by S3)
 *
 * A DIRECTORY PER MODULE, A FILE PER BINDING (section 6).  `<Module>` is the
 * dotted module name used as ONE directory, never split on its dots, so
 * `ls .ermine/preview` lists modules and `Layout.Widgets.Foo` is one entry
 * rather than three nested ones.
 *
 * `schemaRef` is what goes in the params file's own `"$schema"` key: a
 * RELATIVE `./<binding>.schema.json`, because the two files are siblings and
 * VS Code's JSON language service resolves a relative `$schema` against the
 * document.  Nothing is written into the user's `json.schemas` setting.
 *
 * THE REFUSALS, each named so the glue can act on it and each with a sentence
 * for the developer:
 *   `no-pick`            there is nothing to derive a path from;
 *   `no-workspace-folder`/`outside-workspace` (G1) the report is not inside a
 *                        workspace folder, so there is nowhere we may write;
 *   `no-module`          (G6) `ermine/preview/reports` could not name the
 *                        module, so there is no directory name;
 *   `unsafe-module`/`unsafe-binding` (G3) the name is not a plain identifier;
 *   `reserved-name`      (G4) a Windows device name.
 * In every case the caller keeps rendering with the inline `{}` and says so
 * once -- a params file is a convenience, never a precondition.
 *
 * SYMLINKS ARE OUT OF SCOPE HERE AND ARE S3'S.  Containment is decided by
 * comparing STRINGS, which is all a pure function can do: a symlink inside
 * the workspace folder pointing out of it passes this test and would be
 * written through.  Resolving that needs `realpath`, i.e. the disk, i.e. the
 * glue -- S3 resolves before it writes, and this function's answer is a
 * candidate path, not a permission.
 *
 * KNOWN AND ACCEPTED (U4, review G2): the path is keyed by MODULE, not by
 * file, so two files declaring `module Sales` under different roots share one
 * params file.  A path hash would separate them and make the file unreadable
 * and unreviewable, and the file is meant to be committed and read.
 *
 * @param {object} pick a `makePick` value
 * @param {string} folderPath the workspace folder that owns the report
 * @param {"posix"|"win32"=} flavour the path flavour, default the host's
 */
function paramsPaths(pick, folderPath, flavour) {
  const p = pathFlavour(flavour);
  if (!pick || typeof pick !== "object") {
    return problem("no-pick", "No report is picked, so there is no params file to read or write.");
  }
  if (typeof folderPath !== "string" || !folderPath.trim()) {
    return problem("no-workspace-folder",
                   "This report is not in any open workspace folder, so the preview will not create a " +
                   "params file for it; it renders with empty parameters instead.");
  }
  if (!isInsideFolder(p, folderPath, pick.fsPath)) {
    return problem("outside-workspace",
                   'The report "' + printable(pick.fsPath) + '" is not inside the workspace folder "' +
                   printable(folderPath) + '", so the preview will not create a params file for it; ' +
                   "it renders with empty parameters instead.");
  }
  if (!pick.module) {
    return problem("no-module",
                   "The module this file declares is not known yet, and a params file is stored under its " +
                   "module name, so none is written; the report renders with empty parameters.");
  }
  const moduleName = String(pick.module);
  const binding = String(pick.binding === undefined || pick.binding === null ? "" : pick.binding);
  if (moduleName.length > MAX_NAME_LENGTH || !SAFE_MODULE.test(moduleName)) {
    return problem("unsafe-module",
                   'The module name "' + printable(moduleName) + '" cannot be a directory name: a params ' +
                   "directory is a dotted run of plain names (letters, digits, _ and ') of at most " +
                   MAX_NAME_LENGTH + " characters. The report renders with empty parameters.");
  }
  if (binding.length > MAX_NAME_LENGTH || !SAFE_NAME.test(binding)) {
    return problem("unsafe-binding",
                   'The binding "' + printable(binding) + '" cannot be a file name: a params file is named ' +
                   "after a plain binding (a letter or _, then letters, digits, _ and ') of at most " +
                   MAX_NAME_LENGTH + " characters, so an operator binding has no params file. " +
                   "The report renders with empty parameters.");
  }
  const paramsName = binding + ".params.json";
  const schemaName = binding + ".schema.json";
  // Only the segments WE mint are checked: the workspace folder's own
  // segments already exist on the developer's disk, so they are by
  // construction creatable there.
  const minted = PREVIEW_SEGMENTS.concat([moduleName, paramsName, schemaName]);
  for (const segment of minted) {
    if (isReservedDeviceName(segment)) {
      return problem("reserved-name",
                     'The name "' + printable(segment) + '" is a reserved device name on Windows (' +
                     RESERVED_DEVICE_NAMES.slice(0, 4).join(", ") + ", COM1-9, LPT1-9), so a params file " +
                     "could not be created there on a Windows machine. The report renders with empty " +
                     "parameters; rename the module or the binding.");
    }
  }
  const previewDir = p.join(folderPath, PREVIEW_SEGMENTS[0], PREVIEW_SEGMENTS[1]);
  const dir = p.join(previewDir, moduleName);
  const paths = {
    previewDir: previewDir,
    dir: dir,
    paramsPath: p.join(dir, paramsName),
    schemaPath: p.join(dir, schemaName),
    // U7: the generated `.gitignore` sits at `.ermine/preview/`, beside every
    // module's directory, so ONE file covers every generated `*.schema.json`
    // and WP-13/WP-14's `*.db` in whatever workspace folder they land in.
    gitignorePath: p.join(previewDir, ".gitignore"),
    schemaRef: "./" + schemaName,
  };
  // BELT AND BRACES, and the property test's teeth: every path answered is
  // inside the folder it was derived from. The whitelists above already make
  // traversal unreachable; this makes "unreachable" an assertion rather than
  // a claim, and it is the last thing that runs before a caller writes.
  for (const key of ["previewDir", "dir", "paramsPath", "schemaPath", "gitignorePath"]) {
    if (!isInsideFolder(p, folderPath, paths[key])) {
      return problem("outside-workspace",
                     "The generated params path would fall outside the workspace folder, so nothing is " +
                     "written; the report renders with empty parameters.");
    }
  }
  return paths;
}

/**
 * Does saving THIS file mean re-rendering THIS pick? (review G9, D7's sibling)
 *
 * A params file is not a module, so the server's `invalidated` can never name
 * it -- the trigger has to be the client's own, and the client's own has to
 * compare two paths.  On win32 that compare is case-INSENSITIVE, because
 * `report.params.json` and `Report.Params.JSON` are one file there and a save
 * that did not re-render would look like the feature is broken.
 *
 * A pick with no derivable params file (every `paramsPaths` refusal) never
 * matches: there is no file, so no save of one can be this pick's.
 */
function shouldRerenderOnParamsSave(pick, savedPath, folderPath, flavour) {
  if (typeof savedPath !== "string" || !savedPath) return false;
  const p = pathFlavour(flavour);
  const paths = paramsPaths(pick, folderPath, flavour);
  if (paths.problem) return false;
  return comparablePath(p, savedPath) === comparablePath(p, paths.paramsPath);
}

/**
 * IS THIS SCHEMA ANSWER STILL ABOUT THE REPORT THE USER IS LOOKING AT? (D7)
 *
 * `ermine/schema {uri, binding, roots}` carries no `generation` and no pick
 * identity, so -- unlike a render -- a late answer cannot be recognised as
 * late by the answer alone.  The glue therefore captures the pick AT SEND and
 * hands both to this; an answer whose pick has moved is DROPPED, because
 * acting on it writes `<binding>.schema.json` for a report nobody picked.
 *
 * FOUR FIELDS, NOT TWO, and each for a reason:
 *   `uri` + `binding`  the report itself (`markKey`'s pair);
 *   `module`           the DIRECTORY the schema file would be written into.
 *                      A file whose header changed from `Sales` to `Sales2`
 *                      keeps its uri and its binding and needs a different
 *                      path, and the schema in flight is the old type's;
 *   `roots`            the loader chain, in order.  The root set is the
 *                      render session's discard key (section 2.4), so an
 *                      answer computed under the old roots may describe a
 *                      same-named module from another tree entirely.
 * Dropping a good answer costs one re-request, which the `fx.schema` seam
 * already knows how to make.  Keeping a bad one writes a wrong file.
 */
function isCurrentSchemaAnswer(pickAtSend, pickNow) {
  if (!pickAtSend || typeof pickAtSend !== "object") return false;
  if (!pickNow || typeof pickNow !== "object") return false;
  if (String(pickAtSend.uri) !== String(pickNow.uri)) return false;
  if (String(pickAtSend.binding) !== String(pickNow.binding)) return false;
  const a = pickAtSend.module === null || pickAtSend.module === undefined ? null : String(pickAtSend.module);
  const b = pickNow.module === null || pickNow.module === undefined ? null : String(pickNow.module);
  if (a !== b) return false;
  return rootsFingerprint(pickAtSend.roots) === rootsFingerprint(pickNow.roots);
}

// -- the skeleton ----------------------------------------------------------

/** `format: uuid` -> the nil UUID, which is canonical 8-4-4-4-12 and decodes. */
const NIL_UUID = "00000000-0000-0000-0000-000000000000";

/**
 * `Long` is exported as `{"type":"string","pattern":"^-?[0-9]+$"}`
 * (`json/Schema.scala:331`) -- a decimal STRING, because a JSON number cannot
 * hold every `Long`.  `""` does not match that pattern and the decoder
 * refuses it, so the one pattern the exporter emits is recognised here by its
 * exact text and answered `"0"`.  Any OTHER pattern is a refusal rather than
 * a guess: solving a regular expression is not this function's job, and a
 * skeleton that does not validate is worse than no skeleton.
 */
const LONG_PATTERN = "^-?[0-9]+$";

/** A skeleton must not be built past this depth: a hand-edited or hostile
  * schema can nest deeper than the JavaScript stack, and "the editor's
  * extension host died" is not an acceptable answer to a bad schema file.
  * The `$ref` cycle check below already bounds every schema the exporter can
  * emit; this bounds the ones it cannot. */
const MAX_SKELETON_DEPTH = 200;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * THE SKELETON THE FIRST PICK WRITES, from the exported schema.
 *
 * THE FIRST STEP IS A `$ref` HOP, NOT A PROPERTY WALK (defect D2).  The
 * exporter splices the root schema's own fields next to `$schema`/`$id`
 * (`json/Schema.scala:195`), so for a `data` params type -- every
 * interesting one -- the document is
 *
 *     {"$schema": ..., "$id": "ermine:Sales/Query",
 *      "$ref": "#/$defs/Sales.Query", "$defs": {...}}
 *
 * and the root has NO `properties` at all.  A `$defs` table and a visited set
 * are therefore mandatory, not an optimisation.
 *
 * THE VOCABULARY IS THE EXPORTER'S, and only the exporter's, each case read
 * off `json/Schema.scala` rather than guessed:
 *   `$ref`                 -> hop into `$defs` (`:514`)
 *   `enum`                 -> the FIRST member: an all-nullary `data` is its
 *                             constructor name as a bare string (`:527`)
 *   `oneOf`                -> the first ARM that yields a value: a
 *                             multi-constructor `data` (`:530`), whose arms
 *                             are `{tag, ...}` objects (`:571`, `:598-616`)
 *   `anyOf`                -> `null` when any alternative admits it, else the
 *                             first alternative that yields a value.
 *                             `Nullable`/`Maybe#` export as `[a, null]`
 *                             (`:371`) and a required key of that type gets
 *                             the same "absent" default an optional `Maybe`
 *                             key gets by omission -- see `skeletonWalk`
 *   `const`                -> the value itself: this is what makes a `tag`
 *                             come out right (`:571`)
 *   `prefixItems`          -> one skeleton per position: a tuple (`:376-381`)
 *                             or a positional constructor's `args` (`:610-616`)
 *   `items`                -> `[]`, the shortest array that decodes (`:363`)
 *   `format: date`         -> `today` (U2: no clock in a pure function, so the
 *                             date is an ARGUMENT)
 *   `format: date-time`    -> today at midnight UTC in the EXPORTER'S OWN
 *                             spelling, `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`
 *                             (`json/Encode.scala:203`), which is what the
 *                             decoder's `ISO_OFFSET_DATE_TIME` wants -- an
 *                             offset is mandatory there (`json/Decode.scala:461`)
 *   `format: uuid`         -> the nil UUID (`:338`, `Decode.scala:463`)
 *   `type: object`         -> required properties only, recursively (`:606`)
 *   `string`/`integer`/`number`/`boolean`/`null` -> `""` / `0` / `0` / `false` / `null`
 *
 * OPTIONAL KEYS ARE OMITTED, NOT NULLED.  A `Maybe` field is an OPTIONAL key
 * carrying the payload's schema (`json/Schema.scala:593`), and
 * `docs/JSON-GUIDE.md` shows the 400 a `null` in its place earns:
 * `expected an integer (Int), found null`.  So "not in `required`" means "not
 * in the file", which is also rule 2 above: the smallest value that decodes.
 *
 * RECURSION IS A REFUSAL, NOT A LOOP -- BUT ONLY WHERE IT HAS TO BE.  A
 * required property whose type is being built already has no finite skeleton,
 * so that BRANCH fails, naming the `$defs` entry.  An `oneOf` then tries its
 * next arm, which is why `data Tree = Leaf | Node {left: Tree, right: Tree}`
 * still gets a skeleton (`{"tag":"Leaf","args":[]}`) instead of a refusal.
 * Only when every arm recurses does the whole call answer `{problem}`.
 *
 * A NON-OBJECT ROOT IS NOT AN ERROR (review G5).  `report : Int -> Node` --
 * WP-7's own `WpSpin` fixture -- wants a bare number, an all-nullary enum
 * wants a bare string.  Those get their value and `embeddable: false`, which
 * says NO `$schema` KEY CAN BE PUT IN THEM: a JSON number has nowhere to put
 * one.  The caller states that the editor cannot validate such a file.
 *
 * @param {object} schema the exported schema document
 * @param {string} today `YYYY-MM-DD`, the glue's clock
 * @param {string=} schemaRef `./<binding>.schema.json`, if one is to be embedded
 * @returns {{value: any, embeddable: boolean}|{problem: {reason, message}}}
 */
function skeletonFrom(schema, today, schemaRef) {
  if (!isPlainObject(schema)) {
    return problem("not-a-schema",
                   "The params schema the server answered is not a JSON object, so no skeleton can be " +
                   "derived from it.");
  }
  if (typeof today !== "string" || !ISO_DATE.test(today)) {
    return problem("bad-today",
                   "A skeleton needs today's date as YYYY-MM-DD to fill in a date field; it was given " +
                   '"' + printable(today) + '".');
  }
  const defs = isPlainObject(schema.$defs) ? schema.$defs : {};
  const walked = skeletonWalk(schema, defs, today, Object.create(null), 0);
  if (walked.fail) return { problem: walked.fail };
  const value = walked.ok;
  const embeddable = isPlainObject(value);
  if (embeddable && typeof schemaRef === "string" && schemaRef) {
    // `$schema` FIRST, so the file opens with the line that makes the editor
    // validate the rest of it. D1/U1 make that line legal: `schemaFileFor`
    // injects a `$schema` property into the object the root `$ref` names,
    // because `additionalProperties: false` only ever sees its own sibling
    // `properties` and would otherwise squiggle the one line we added.
    return { value: withLeadingKey("$schema", schemaRef, value), embeddable: true };
  }
  return { value: value, embeddable: embeddable };
}

/** Every walk answers `{ok}` or `{fail}`; `oneOf`/`anyOf` are the only things
  * that look at a `fail` and carry on, which is what makes a recursive type
  * with a nullary arm work. */
function skelOk(value) { return { ok: value }; }
function skelFail(reason, message) { return { fail: { reason: String(reason), message: String(message) } }; }

function isPlainObject(v) {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

/**
 * ADD A KEY THAT CAME OUT OF JSON, WITHOUT LETTING IT RUN A SETTER (the S1
 * review's I-1).
 *
 * `JSON.parse` makes `__proto__` an ORDINARY OWN property, and `Object.keys`
 * hands it over like any other -- but `obj[key] = value` on a plain object
 * then reaches `Object.prototype`'s `__proto__` SETTER, which re-prototypes
 * the object and stores nothing.  MEASURED on Node 24 before the fix:
 * `paramsToSend('{"__proto__":{"polluted":1},"a":1}')` answered `{"a":1}` --
 * the key SILENTLY GONE -- with `"polluted" in params` TRUE.  The wire payload
 * and the fingerprint were unaffected (`JSON.stringify` and `Object.keys`
 * ignore a prototype), and `Object.prototype` itself was never touched, but
 * the glue S2/S3 is about to write reads this object with `in`, `for...in`
 * and spread.  `defineProperty` takes the key as data, every time.
 *
 * In `skeletonObject` the same assignment produced a WRONG DIAGNOSIS rather
 * than a lost key: a required `__proto__` whose value is not an object was
 * dropped by the setter and then reported "unsatisfiable", which it is not.
 *
 * `__proto__` cannot be an Ermine field name (`identStart = letter`), so a
 * real params type never reaches this; a hand-edited params file does.
 */
function defineKey(target, key, value) {
  Object.defineProperty(target, key, { value: value, enumerable: true, writable: true, configurable: true });
}

/**
 * `{first: value, ...rest}` without `Object.assign`, which copies with
 * `[[Set]]` and therefore hits the same `__proto__` setter `defineKey` exists
 * to avoid.  Key order is the point: the new key comes FIRST, which is what
 * puts `"$schema"` at the top of a params file and at the top of an injected
 * `properties`.
 */
function withLeadingKey(key, value, rest) {
  const out = {};
  defineKey(out, key, value);
  if (isPlainObject(rest)) {
    for (const k of Object.keys(rest)) if (k !== key) defineKey(out, k, rest[k]);
  }
  return out;
}

function skeletonWalk(node, defs, today, visiting, depth) {
  if (depth > MAX_SKELETON_DEPTH) {
    return skelFail("too-deep",
                    "The params schema nests more than " + MAX_SKELETON_DEPTH + " levels deep; no " +
                    "skeleton is derived from it.");
  }
  // A boolean schema: `true` (and `{}`) allow anything, `false` allows
  // nothing. The exporter emits `{}` for a `Json`-typed position
  // (`json/Schema.scala:300`), where `null` is a value the decoder takes.
  if (node === true) return skelOk(null);
  if (node === false) {
    return skelFail("unsatisfiable", "Part of the params schema allows no value at all (`false`).");
  }
  if (!isPlainObject(node)) {
    return skelFail("not-a-schema", "Part of the params schema is not a JSON object, so it has no skeleton.");
  }

  if (typeof node.$ref === "string") {
    const name = defNameOf(node.$ref);
    if (name === null) {
      return skelFail("unsupported",
                      'The params schema has a reference this preview cannot follow: "' +
                      printable(node.$ref) + '" (only "#/$defs/<name>" is used by the exporter).');
    }
    if (visiting[name]) {
      return skelFail("recursive",
                      "The type " + printable(name) + " contains itself in a required position, so it has " +
                      "no finite default value; write the params file by hand.");
    }
    if (!Object.prototype.hasOwnProperty.call(defs, name)) {
      return skelFail("unsupported",
                      "The params schema refers to " + printable(name) + ", which it does not define.");
    }
    const nested = Object.create(visiting);
    nested[name] = true;
    return skeletonWalk(defs[name], defs, today, nested, depth + 1);
  }

  if (Object.prototype.hasOwnProperty.call(node, "const")) return skelOk(node.const);

  if (Array.isArray(node.enum)) {
    if (!node.enum.length) {
      return skelFail("unsatisfiable", "Part of the params schema is an empty `enum`, which no value satisfies.");
    }
    return skelOk(node.enum[0]);
  }

  // The two branching keywords, and the ONLY places a failed branch is not
  // fatal. `oneOf` is a multi-constructor `data` (or a bare relation's two
  // delivery arms); `anyOf` is a `Nullable`/`Maybe#` (`json/Schema.scala:371`).
  //
  // `anyOf` WITH A NULL ARM ANSWERS `null`, and the S1 review is why the rule
  // now reads this way rather than "the first alternative that yields".
  // Rule 2 of this section is "the smallest value that decodes", and `null` is
  // smaller than any payload; more to the point it is the SAME answer an
  // optional `Maybe` key gets by being left out. The alternative was actively
  // WRONG as a default, not merely longer: a required `Nullable String` filter
  // would have started life as `""`, which is not "no filter" but "match the
  // empty string", and a required `Nullable Date` would have started at today,
  // which is a real date range nobody asked for. `oneOf` keeps the
  // first-that-yields rule: the exporter never puts a null arm in one, and a
  // recursive union needs its base case.
  for (const key of ["oneOf", "anyOf"]) {
    if (Array.isArray(node[key])) {
      if (!node[key].length) {
        return skelFail("unsatisfiable",
                        "Part of the params schema has an empty `" + key + "`, which no value satisfies.");
      }
      if (key === "anyOf" && node[key].some(admitsNull)) return skelOk(null);
      let last = null;
      for (const alternative of node[key]) {
        const attempt = skeletonWalk(alternative, defs, today, visiting, depth + 1);
        if (!attempt.fail) return attempt;
        last = attempt;
      }
      return last;
    }
  }

  const type = Array.isArray(node.type) ? node.type[0] : node.type;
  switch (type) {
    case "object":  return skeletonObject(node, defs, today, visiting, depth);
    case "array":   return skeletonArray(node, defs, today, visiting, depth);
    case "string":  return skeletonString(node, today);
    case "integer":
    case "number":  return skelOk(clampNumber(node));
    case "boolean": return skelOk(false);
    case "null":    return skelOk(null);
    default:
      // No `type` and no keyword above: the exporter's `Json` position, which
      // accepts anything the parser can hold, and `null` is the shortest.
      return skelOk(null);
  }
}

/** Is this alternative the `{"type":"null"}` arm the exporter writes for a
  * `Nullable`/`Maybe#` (`json/Schema.scala:371`)? A bare `true` schema admits
  * null too, and so does an unconstrained `{}` -- both are "anything goes", so
  * both are honest null arms. */
function admitsNull(alternative) {
  if (alternative === true) return true;
  if (!isPlainObject(alternative)) return false;
  if (alternative.type === "null") return true;
  return Object.keys(alternative).length === 0;
}

/** `#/$defs/<name>` -> `<name>`; anything else -> null. The exporter writes no
  * other pointer shape (`json/Schema.scala:514`) and a `$defs` name is
  * sanitised to letters, digits, `_` and `.`, so no RFC 6901 escape can occur. */
function defNameOf(ref) {
  const prefix = "#/$defs/";
  if (typeof ref !== "string" || ref.indexOf(prefix) !== 0) return null;
  const name = ref.slice(prefix.length);
  if (!name || name.indexOf("/") >= 0) return null;
  return name;
}

function skeletonObject(node, defs, today, visiting, depth) {
  const properties = isPlainObject(node.properties) ? node.properties : {};
  const required = Array.isArray(node.required) ? node.required.map(String) : [];
  const open = node.additionalProperties !== false;
  const value = {};
  // DECLARATION ORDER, not `required` order: the exporter writes a
  // constructor's properties in the order the fields were declared
  // (`json/Schema.scala:601`), and a skeleton the developer reads next to the
  // source should be in the same order. The `tag` of a multi-constructor arm
  // is first in `properties`, so it comes out first here too.
  for (const key of Object.keys(properties)) {
    if (required.indexOf(key) < 0) continue;                  // a `Maybe` key: OMITTED
    const attempt = skeletonWalk(properties[key], defs, today, visiting, depth + 1);
    if (attempt.fail) return attempt;
    defineKey(value, key, attempt.ok);                          // review I-1
  }
  for (const key of required) {
    if (Object.prototype.hasOwnProperty.call(value, key)) continue;
    if (!open) {
      return skelFail("unsatisfiable",
                      'The params schema requires the key "' + printable(key) + '" and forbids it in the ' +
                      "same breath, so no value satisfies it.");
    }
    // A required key with no schema of its own is unconstrained, so `null`
    // satisfies it. Unreachable from this exporter, which never requires a
    // key it does not describe; kept so a hand-edited schema does not throw.
    defineKey(value, key, null);                                // review I-1
  }
  return skelOk(value);
}

function skeletonArray(node, defs, today, visiting, depth) {
  if (Array.isArray(node.prefixItems)) {
    const value = [];
    for (const item of node.prefixItems) {
      const attempt = skeletonWalk(item, defs, today, visiting, depth + 1);
      if (attempt.fail) return attempt;
      value.push(attempt.ok);
    }
    return skelOk(value);
  }
  // `maxItems: 0` is the exporter's unit `()` and its nullary positional
  // constructor's `args` (`json/Schema.scala:378`, `:610`); `[]` is what the
  // decoder wants for both ("an array of exactly 0").
  const minItems = typeof node.minItems === "number" && node.minItems > 0 ? Math.floor(node.minItems) : 0;
  if (minItems === 0) return skelOk([]);
  if (node.items === undefined) return skelOk([]);
  const attempt = skeletonWalk(node.items, defs, today, visiting, depth + 1);
  if (attempt.fail) return attempt;
  const value = [];
  for (let i = 0; i < minItems; i++) value.push(attempt.ok);
  return skelOk(value);
}

function skeletonString(node, today) {
  if (node.format === "date") return skelOk(today);
  // The exporter's own spelling, so the decoder's ISO_OFFSET_DATE_TIME takes
  // it: the offset is not optional there.
  if (node.format === "date-time") return skelOk(today + "T00:00:00.000Z");
  if (node.format === "uuid") return skelOk(NIL_UUID);
  if (typeof node.pattern === "string") {
    if (node.pattern === LONG_PATTERN) return skelOk("0");
    return skelFail("unsupported",
                    "Part of the params schema constrains a string to the pattern " +
                    printable(node.pattern) + ", which this preview cannot invent a value for; " +
                    "write the params file by hand.");
  }
  const min = typeof node.minLength === "number" && node.minLength > 0 ? Math.floor(node.minLength) : 0;
  if (min === 0) return skelOk("");
  const max = typeof node.maxLength === "number" ? Math.floor(node.maxLength) : min;
  if (max < min) {
    return skelFail("unsatisfiable",
                    "Part of the params schema asks a string to be both longer than " + min +
                    " and shorter than " + max + " characters.");
  }
  // `Char` is `minLength: 1, maxLength: 1` (`json/Schema.scala:335`) and any
  // character does; `x` is one.
  return skelOk("x".repeat(min));
}

/** `0` unless the schema puts it out of range: `Short` and `Byte` carry a
  * `minimum`/`maximum` (`json/Schema.scala:329-330`) that 0 is inside, so
  * this only ever moves for a hand-written schema. */
function clampNumber(node) {
  let value = 0;
  if (typeof node.minimum === "number" && value < node.minimum) value = node.minimum;
  if (typeof node.maximum === "number" && value > node.maximum) value = node.maximum;
  return value;
}

// -- the schema file -------------------------------------------------------

/**
 * A JSON value copied field by field, key order kept.  Used so nothing this
 * section answers can share structure with -- let alone mutate -- the schema
 * the server sent, which the glue keeps and may hand out again.
 *
 * `defineKey`, not `out[key] =`, for the reason I-1 gives: a schema read off
 * disk can hold a key literally named `__proto__`, and an assignment would
 * silently drop it and re-prototype the copy.  MEASURED before this fix: a
 * `properties` key called `__proto__` disappeared from the written file, and a
 * `$defs` ENTRY called `__proto__` vanished entirely, leaving the root `$ref`
 * dangling.  Neither is reachable from the exporter -- `Schema.defName` builds
 * `<module>.<type>` and `__proto__` is not an Ermine field name -- and both
 * failed in the SAFE direction (a key the editor then refuses, rather than one
 * it wrongly allows), so this is hygiene rather than a hole.  It is still
 * wrong, and the fix is one word.
 */
function cloneJson(value) {
  if (Array.isArray(value)) return value.map(cloneJson);
  if (isPlainObject(value)) {
    const out = {};
    for (const key of Object.keys(value)) defineKey(out, key, cloneJson(value[key]));
    return out;
  }
  return value;
}

/**
 * THE `.schema.json` FILE, from the schema the server exported.
 *
 * TWO EDITS, BOTH DECIDED BY THE USER, and nothing else touched:
 *
 * U1 -- `$id` IS DROPPED.  The exporter names it `ermine:Sales/Query`
 * (`json/Schema.scala:191`), a CUSTOM-SCHEME base URI, and a fragment-only
 * `#/$defs/X` resolves against whatever base is in scope.  VS Code's JSON
 * language service has had 2020-12 support land in pieces, so whether it
 * resolves a `$ref` under an `ermine:` base is UNVERIFIED BY ANYONE HERE.
 * The file's own path is a perfectly good identity, so the risk is simply
 * removed.  `$defs` and `$ref` stay: recursion needs them.
 *
 * D1/U1 -- `"$schema": {"type": "string"}` IS INJECTED WHERE THE PARAMS FILE'S
 * OWN ROOT OBJECT IS DESCRIBED.  The params file carries a relative
 * `"$schema"` line so the editor knows which schema to use; a record-style
 * params type exports `additionalProperties: false`
 * (`json/Schema.scala:606`); so, without this, the ONE LINE that makes
 * validation work is the first thing validation complains about.
 *
 * "WHERE THE ROOT OBJECT IS DESCRIBED" IS NOT ALWAYS THE `$defs` ENTRY, and
 * D1 only named that one case.  The exporter splices the root schema's fields
 * next to `$schema`/`$id` (`json/Schema.scala:195`), so the root of the
 * document is whatever the params type walks to, and three shapes of it can
 * hold a `$schema` key:
 *
 *   `{"$ref": "#/$defs/Sales.Query"}`   a `data` params type -- D1's case,
 *                                       inject into the `$defs` ENTRY, never
 *                                       into the root: `additionalProperties`
 *                                       constrains keys only against its OWN
 *                                       SIBLING `properties`, so a
 *                                       `properties` added at the root would
 *                                       do precisely nothing;
 *   `{"type":"object","properties":...,"additionalProperties":false}`
 *                                       a RECORD params type
 *                                       (`report : {..(|a,b|)} -> Node`,
 *                                       `json/Schema.scala:412-419`), inlined
 *                                       at the document root -- here the root
 *                                       IS the sibling, so it is injected
 *                                       there;
 *   `{"oneOf": [arm, arm]}`             a multi-constructor `data`
 *                                       (`:530`): EVERY arm is injected,
 *                                       because the developer may retag the
 *                                       file to any of them and the `$schema`
 *                                       line has to survive that.  An
 *                                       optional key added to every arm
 *                                       cannot make two arms match one value:
 *                                       the `tag` consts still discriminate.
 *
 * AND A FOURTH RULE THAT CUTS ACROSS ALL THREE (the S1 review's D-1): a
 * `$defs` entry that ALSO describes a nested position is never injected in
 * place -- a root-level COPY of it is, and the root `$ref` is pointed at the
 * copy, so a nested `$schema` stays as illegal in the editor as it is on the
 * wire.  `cloneForRoot` below has the measurement and the reasoning.
 *
 * LEFT ALONE, deliberately:
 *   an OPEN object (a `Spread` field, `additionalProperties: true`) already
 *   admits any key, so there is nothing to inject and injecting would change
 *   what the file means;
 *   a NON-OBJECT root (`Int`, an all-nullary enum, a tuple) has no properties
 *   to inject into and no `$schema` key can appear in its params file either
 *   (`skeletonFrom`'s `embeddable: false` says the same thing);
 *   an object that already declares a `$schema` property.
 *
 * Never mutates its input, and is IDEMPOTENT: the file is rewritten whenever
 * the params type changes (D8's write-if-different compares its bytes), so
 * "run it twice, get the same bytes" is a property, not a nicety.
 */
function schemaFileFor(schema) {
  if (!isPlainObject(schema)) return schema;
  const out = cloneJson(schema);
  delete out.$id;
  allowSchemaKey(out, isPlainObject(out.$defs) ? out.$defs : {}, out, Object.create(null), 0);
  return out;
}

/**
 * Walk from a schema node to the object(s) THE INSTANCE'S ROOT could be, and
 * let each closed one carry a `$schema` key.  Answers whether it injected
 * anything, which is what decides whether a clone was worth minting.  Mutates
 * the CLONE `schemaFileFor` made and nothing else.
 *
 * THE `seen` SET is over `$defs` names, so a recursive type is visited once;
 * the exporter never chains one `$ref` to another, but following them costs
 * nothing and a hand-edited file may.
 *
 * IT NEVER DESCENDS INTO `properties`, which is what keeps a nested field
 * from being injected -- and the review's D-1 is the other half of that same
 * rule: see `cloneForRoot` below.
 */
function allowSchemaKey(node, defs, doc, seen, depth) {
  if (!isPlainObject(node) || depth > MAX_SKELETON_DEPTH) return false;
  if (typeof node.$ref === "string") {
    const name = defNameOf(node.$ref);
    if (name === null || seen[name]) return false;
    if (!Object.prototype.hasOwnProperty.call(defs, name)) return false;
    const nested = Object.create(seen);
    nested[name] = true;
    if (!isReferencedElsewhere(doc, node, name)) {
      // Reachable ONLY from the instance's root, so the entry itself may
      // carry the key: this is Sales's case and the common one.
      return allowSchemaKey(defs[name], defs, doc, nested, depth + 1);
    }
    return cloneForRoot(node, defs, doc, name, nested, depth);
  }
  for (const key of ["oneOf", "anyOf"]) {
    if (Array.isArray(node[key])) {
      let injected = false;
      for (const alternative of node[key]) {
        if (allowSchemaKey(alternative, defs, doc, seen, depth + 1)) injected = true;
      }
      return injected;
    }
  }
  if (node.type !== "object") return false;
  if (node.additionalProperties !== false) return false;         // already open
  if (!isPlainObject(node.properties)) return false;
  if (Object.prototype.hasOwnProperty.call(node.properties, "$schema")) return false;
  node.properties = withLeadingKey("$schema", { type: "string" }, node.properties);
  return true;
}

/**
 * D-1 (the S1 REVIEW, 2026-09-21, MEASURED): A SHARED `$defs` ENTRY MUST NOT
 * BE INJECTED IN PLACE -- IT WOULD MAKE A **NESTED** `$schema` LEGAL IN THE
 * EDITOR THAT THE SERVER REFUSES.
 *
 * The committed golden `core/src/test/resources/schema/UserTree.schema.json`
 * is the case: `Test.Tree` is the root `$ref`'s target AND what the `Node`
 * arm's `args.prefixItems` refer to.  Injecting into that one entry lets the
 * editor accept
 *
 *     {"tag":"Node","args":[{"$schema":"...","tag":"Leaf","args":[0]}, ...]}
 *
 * which `paramsToSend` does NOT strip -- G20's strip is top-level-only, on
 * purpose -- and which the decoder then refuses: `json/Decode.scala:755-756`
 * (`closed`) via `:848-849`, MEASURED against a real server by the review as
 * `400 "the key \"$schema\" is not allowed here"`.  That is exactly the
 * failure this whole edit exists to prevent, with the sign reversed.
 *
 * THE FIX IS A ROOT-LEVEL CLONE.  When the entry is reachable from anywhere
 * but the root, its skeleton-carrying copy is minted under a NEW `$defs`
 * name, the injection goes into the COPY, and the ROOT `$ref` is pointed at
 * it.  The shared entry is left untouched, so every NESTED occurrence still
 * forbids `$schema` -- editor and server agree again, in both directions.
 * The copy's own inner `$ref`s still name the ORIGINAL, which is what makes
 * one level of `$schema` and no more.
 *
 * THE CLONE'S NAME CANNOT COLLIDE WITH AN EXPORTER NAME.  `Schema.defName`
 * runs every name through `sanitise` (`json/Schema.scala:721-722`), which
 * replaces everything that is not a letter, a digit, `_` or `.` with `_` --
 * so a `-` can never appear in an exported `$defs` name.  It is also
 * unreserved in a URI (RFC 3986) and needs no JSON Pointer escaping (only `~`
 * and `/` do), so `#/$defs/<name>-params-root` is a valid `$ref`.
 *
 * NOTHING IS CLONED SPECULATIVELY: the copy is made, the injection is tried
 * on it, and if nothing was injected (an open object, an enum, a tuple) the
 * copy is thrown away and the file is left as the exporter wrote it.  That is
 * also what keeps `schemaFileFor` IDEMPOTENT: on a second run the root `$ref`
 * already names the copy, the copy is referenced by nothing else, and its
 * `properties` already declares `$schema`, so no second copy is minted.
 *
 * ONE OBLIGATION THIS PUTS ON S3, AND IT IS THE ONLY ONE IN THIS SECTION.
 * A copy tracks the entry it was cloned from ONLY WITHIN THE CALL THAT MADE
 * IT.  `schemaFileFor` is a pure function of what it is handed; it does not
 * and cannot diff a copy against a later version of its original.  So **S3
 * MUST ALWAYS PASS THE SERVER'S FRESH `ermine/schema` ANSWER AND MUST NEVER
 * READ ITS OWN WRITTEN `.schema.json` BACK INTO THIS FUNCTION.**  Feed the
 * written file back after the params type has changed and the copy silently
 * keeps the OLD shape while the shared entry beside it carries the new one --
 * MEASURED (a field added to the original does not appear in the copy), and
 * pinned by a test that documents the hazard rather than forbidding it.  The
 * fresh answer costs one request and is what D8's write-if-different compares
 * against anyway.
 */
function cloneForRoot(refNode, defs, doc, name, seen, depth) {
  const copy = cloneJson(defs[name]);
  if (!allowSchemaKey(copy, defs, doc, seen, depth + 1)) return false;
  const copyName = freeDefName(defs, name + "-params-root");
  defs[copyName] = copy;
  refNode.$ref = "#/$defs/" + copyName;
  return true;
}

/** `<base>`, else `<base>-`, `<base>--`, ... -- a hand-edited file that has
  * already taken the name does not get its entry overwritten. */
function freeDefName(defs, base) {
  let name = base;
  while (Object.prototype.hasOwnProperty.call(defs, name)) name += "-";
  return name;
}

/**
 * Is `#/$defs/<name>` named by any `$ref` in the document OTHER than this
 * one?  If it is, the entry describes a NESTED position as well as the root
 * and must not be injected in place (see `cloneForRoot`).
 *
 * The whole document is scanned rather than only the positions the injector
 * walks, because the question is about every place a VALUE can sit, and the
 * injector deliberately does not visit those.
 */
function isReferencedElsewhere(doc, refNode, name) {
  const target = "#/$defs/" + name;
  let found = false;
  const visit = (node) => {
    if (found || !node || typeof node !== "object") return;
    if (Array.isArray(node)) { node.forEach(visit); return; }
    if (node !== refNode && node.$ref === target) { found = true; return; }
    for (const key of Object.keys(node)) visit(node[key]);
  };
  visit(doc);
  return found;
}

/**
 * The bytes of the `.schema.json` file.
 *
 * Two spaces and a TRAILING NEWLINE: the file is generated on every change of
 * the params type, and D8 says do not write it when it has not changed -- a
 * comparison that is only meaningful if the same schema always renders to the
 * same bytes.  The trailing newline is so `git diff` and every POSIX tool
 * that reads the file in a checkout behave.
 */
function schemaFileText(value) {
  return JSON.stringify(value, null, 2) + "\n";
}

/**
 * The generated `.ermine/preview/.gitignore` (U7).
 *
 * U7 IS BOTH FILES, AND THIS IS ONE OF THEM: a self-contained
 * `.ermine/preview/.gitignore` beside the generated files, PLUS the line in
 * the checkout's root `.gitignore`.  The second file is not wrong and is not
 * dropped -- it is simply not S1's: writing either of them is S3's job, and
 * only the TEXT and the PATH of this one live here.  The generated file is
 * needed because the repo line alone is inert in every OTHER workspace folder
 * and leaves WP-13/WP-14's file-backed `local.db` tracked; the repo line is
 * needed because a checkout should say what it ignores in the place people
 * look.  The params files themselves are NOT ignored by either -- they are
 * the point, they are the default a fresh clone renders, and `git status`
 * showing them is a done-when.
 */
const paramsGitignoreText = [
  "# Generated by the Ermine preview (tracker/JSON-WIDGET-PLAYGROUND.md, section 6, U7).",
  "#",
  "# The *.params.json files under here are ORDINARY COMMITTED SOURCE: they are",
  "# the parameters a fresh clone renders the report with. What is ignored is",
  "# only what the preview generates from them or beside them:",
  "#   *.schema.json  rewritten from the report's parameter type on every change",
  "#   *.db           the preview's own local database file",
  "*.schema.json",
  "*.db",
  "",
].join("\n");

// -- what is actually sent -------------------------------------------------

/** U6: one mebibyte of params, measured in the UTF-8 bytes of the FILE.
  * The only other bound is the server's `Wire.MaxFrame` of 64 MiB, over which
  * the reader CLOSES THE CONNECTION (`lsp/Rpc.scala:238`, `:331-337`) -- the
  * render does not fail, the language server goes away. A named refusal a
  * thousand times smaller is the difference between a message and a mystery. */
const PARAMS_MAX_BYTES = 1024 * 1024;

/**
 * A TOP-LEVEL KEY THAT LOOKS LIKE A CREDENTIAL (U5, review G13).
 *
 * Only top-level keys, and only a warning.  A params file is committed AND
 * the render body reaches `ERMINE_LSP_LOG` (clipped at 2000 characters,
 * `lsp/Rpc.scala:244`; `Rpc.Redacted` holds `ermine/preview/connect` and nothing
 * else), so a password in one is a password in two places that outlive the
 * session.  It is NOT a refusal: a report may legitimately take a `token`
 * parameter, and the user decided (U5) that a block the developer cannot
 * override is the wrong trade.
 *
 * THE PATTERN IS THE USER'S, VERBATIM, AND IS NOT WIDENED HERE.  It over-warns
 * (`passenger`, `bypass`, `tokenize`) and under-warns (`connectionString`,
 * `dsn`, `jwt`, `auth`, `bearer`, `privateKey`, `credential`).  The S1 review
 * found the second list, and the answer is to say so in the WARNING rather
 * than to quietly extend a rule the user wrote down: `credentialKeyWarning`
 * now states what the check actually looks for, so nobody reads its silence
 * as a clearance.  Widening it is available to the user; section 6 records it.
 */
const CREDENTIAL_KEY = /pass|pwd|secret|token|api[-_]?key/i;

/**
 * A LEADING UTF-8 BYTE ORDER MARK IS NOT A SYNTAX ERROR (the S1 review's I-2).
 *
 * `JSON.parse` refuses U+FEFF, and VS Code writes one on every save whenever
 * `files.encoding` is `utf8bom` -- not rare on the Windows machines section 10
 * names as the deployment target.  The developer would be looking at a
 * syntactically perfect file and reading "the params file is not valid JSON",
 * which is the one thing a named refusal must never do.  One BOM is dropped;
 * anything else stays, so a genuine syntax error still reports itself.
 *
 * THE BYTE CAP COUNTS THE BOM.  It is measured on the text AS READ, before
 * this runs, because the cap is a bound on the FILE the glue picked up off the
 * disk; three bytes out of a mebibyte is not worth a second rule, and "the
 * file is N bytes" in the refusal then matches what the developer's own tools
 * report.
 */
function withoutBom(text) {
  return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

/**
 * The sentence shown once per file when `paramsToSend` warns.
 * Exported so the glue cannot reword the rule into something weaker.
 */
function credentialKeyWarning(keys) {
  const named = (Array.isArray(keys) ? keys : []).map((k) => '"' + printable(k) + '"');
  const subject = named.length === 1 ? "The key " + named[0] + " looks"
                                     : "The keys " + named.join(", ") + " look";
  return subject + " like a credential. A params file is committed to the repository and its value is " +
         "written to the language server's log, so a password or an API token in one is a secret in " +
         "both. Nothing is blocked: if the report really takes it as a parameter, ignore this. " +
         "This is a check on the KEY NAME only -- it looks for pass, pwd, secret, token and apiKey, " +
         "so it says nothing about a key called connectionString, dsn, jwt, auth, bearer, " +
         "privateKey or credential.";
}

/**
 * THE FILE'S TEXT -> WHAT GOES IN `params` ON THE WIRE, or a named refusal.
 *
 * THE ORDER OF THE CHECKS IS PART OF THE DESIGN:
 *   1. THE CAP FIRST (U6), on the TEXT's UTF-8 bytes, because the point of a
 *      cap is not to parse the thing;
 *   2. an EMPTY or whitespace-only file, before the parser, because
 *      `JSON.parse("")` says "Unexpected end of JSON input", which tells a
 *      developer looking at an empty file nothing they did not know;
 *   3. PARSE.  Invalid JSON is a REFUSAL and the render DOES NOT HAPPEN
 *      (review G7): the alternative is rendering yesterday's parameters under
 *      today's file, which looks like it worked.  The parser's own message
 *      travels with the refusal, and the JSON editor's squiggle carries the
 *      position;
 *   4. STRIP `$schema`, and ONLY the top-level one, and ONLY when the root is
 *      an object (review G20).  Every request key is closed
 *      (`json/Runner.scala:101-103`), so the line that makes the EDITOR work
 *      would be a 400 from the SERVER.  A consequence worth stating: a params
 *      type with a `Spread` field is open, so it could in principle have a
 *      genuine `$schema` field -- and it cannot have one here, ever;
 *   5. WARN about credential-looking keys (U5).  Never a refusal.
 *
 * AN EMPTY FILE IS A NAMED REFUSAL, NOT AN EMPTY OBJECT, and this is the one
 * decision here the tracker did not settle.  `docs/JSON-GUIDE.md` says a
 * MISSING `params` key decodes as `null` -- but a missing key is a file that
 * does not EXIST, which is S3's case and which WP-7 already measured an answer
 * for (`{}`, whose 400 names the first key the developer must supply).  A file
 * that exists and is empty is a different event: a truncated write, an editor
 * crash, a `git checkout` caught mid-flight.  Rendering it as `{}` would
 * silently throw away parameters the developer believes are there and show a
 * document that looks fine.  So it is named, and it does not render -- the
 * same answer invalid JSON gets, for the same reason.
 *
 * @param {string} text the params file's contents
 * @param {number=} maxBytes the cap, default `PARAMS_MAX_BYTES`
 * @returns {{params: any, warnings: string[]}|{problem: {reason, message}}}
 */
function paramsToSend(text, maxBytes) {
  const cap = typeof maxBytes === "number" && maxBytes > 0 ? maxBytes : PARAMS_MAX_BYTES;
  if (typeof text !== "string") {
    return problem("not-text", "The params file could not be read as text.");
  }
  const bytes = Buffer.byteLength(text, "utf8");
  if (bytes > cap) {
    return problem("too-large",
                   "The params file is " + bytes + " bytes and the preview sends at most " + cap +
                   " bytes of parameters, so it was not sent and the report was not rendered.");
  }
  if (!text.trim()) {
    return problem("empty",
                   "The params file is empty. An empty file is not JSON; write `{}` in it for a report " +
                   "whose parameters are all optional, or fill in the keys the schema beside it names.");
  }
  let parsed;
  try {
    parsed = JSON.parse(withoutBom(text));
  } catch (err) {
    return problem("invalid-json",
                   "The params file is not valid JSON, so the report was not rendered: " +
                   printable(err && err.message ? err.message : String(err)));
  }
  let params = parsed;
  const warnings = [];
  if (isPlainObject(parsed)) {
    params = {};
    const flagged = [];
    for (const key of Object.keys(parsed)) {
      if (key === "$schema") continue;                          // G20: top-level, object root, only
      defineKey(params, key, parsed[key]);                      // review I-1
      if (CREDENTIAL_KEY.test(key)) flagged.push(key);
    }
    if (flagged.length) warnings.push(credentialKeyWarning(flagged));
  }
  return { params: params, warnings: warnings };
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
  // WP-8 S1: params files, all pure, none of it wired yet.
  paramsPaths,
  shouldRerenderOnParamsSave,
  isCurrentSchemaAnswer,
  skeletonFrom,
  schemaFileFor,
  schemaFileText,
  paramsToSend,
  credentialKeyWarning,
  paramsGitignoreText,
  PARAMS_MAX_BYTES,
  CREDENTIAL_KEY,
  NIL_UUID,
  MAX_NAME_LENGTH,
  MAX_SKELETON_DEPTH,
  RESERVED_DEVICE_NAMES,
};
