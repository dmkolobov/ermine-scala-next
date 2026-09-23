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
    //
    // WP-8 S2 MOVED THE SENTINEL FROM `null` TO `undefined`, AND THE REASON
    // IS A PARAMS FILE THAT REALLY SAYS `null`. "No params" is now spelled
    // `undefined` and still becomes `{}` -- WP-7's measured behaviour, which
    // is what the missing-file case sends. But a report whose parameter type
    // is a `Maybe X` WANTS `null` (`docs/JSON-GUIDE.md:1295-1297`, and S1's
    // skeleton mints exactly that for such a root), and a file holding `null`
    // is a file whose content we must send. Coercing it here would have sent
    // `{}` instead and turned a correct params file into a 400 nobody could
    // explain. Nothing passes `null` any more: `renderNow` passes what it
    // read, and the no-file case passes `{}` itself.
    params: params === undefined ? {} : params,
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
 * WP-8's hook, exported by WP-22 and fed by WP-8 S2: the params a render
 * ACTUALLY SENT, after the `$schema` strip.
 *
 * `undefined` IS "NOTHING WAS SENT" AND `null` IS A VALUE (S2 review M3).
 * The first cut collapsed both into `{}`, which contradicted S2's own
 * sentinel decision one function away (`renderParams`, `markParamsFor`) and
 * MEASURED as a real hole: `fp(null)`, `fp({})` and `fp(undefined)` were one
 * digest, so a report that wedged with NO FILE was not un-held by writing a
 * file holding `null`, and one that wedged on `null` was not un-held by
 * replacing it with `{}` or by deleting the file. A params file whose whole
 * content is `null` is what a `Maybe`-rooted report wants
 * (`docs/JSON-GUIDE.md:1295-1297`), so it is a value like any other.
 *
 * `undefined` still maps to `{}` rather than to a fourth digest, and that is
 * DELIBERATE COMPATIBILITY: every mark WP-22 and 0.1.7 wrote carries
 * `fingerprint({})` because nothing fed this function, and a mark persisted
 * in `workspaceState` by 0.1.7 must keep meaning "no params" when 0.1.8
 * reads it back. So an upgrade behaves as it did: the first render of a
 * restored pick that sends `{}` (no params file) leaves the mark standing,
 * and one that sends anything else clears it.
 */
function paramsFingerprint(params) {
  return fingerprint(params === undefined ? {} : params);
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
 * triggers is asking; a trigger that brings NO EVIDENCE OF CHANGE is refused
 * for a mark that is THIS pick's, and every other trigger is permitted.
 *
 * IT IS STILL ONE FUNCTION, AND SINCE WP-8 S2 IT IS REACHED FROM TWO PLACES
 * (the S2 review's M6, which is the user's own sentence: *"We'd want some
 * sort of confirmation before rendering a report which wedged and was killed
 * the first time around AND IT DIDN'T CHANGE"*).  The second place is
 * `renderNow` itself, immediately after the guard has been fed the params
 * that are about to be sent -- the one moment at which the extension KNOWS
 * whether anything changed, because it has just computed the fingerprint.
 * Adding a second decision would have been the mistake; asking the same
 * question from a second place is not.
 *
 * **THE RULE THAT DECIDES MEMBERSHIP, AND IT IS THE DELTA RE-REVIEW'S D1**:
 *
 *     A TRIGGER MAY STAY OUT OF `UNCONFIRMED_TRIGGERS` ONLY IF, WHENEVER THE
 *     GLUE SCHEDULES IT, THE GUARD EVENT IT FED HAS CLEARED THE MARK.
 *
 * Under that rule the membership is forced, and three of the four "evidence"
 * triggers qualify while the fourth does not:
 *   `invalidated`     the glue schedules IFF `shouldRerenderOnInvalidated`,
 *                     and `guardReduce` clears on exactly that condition --
 *                     one predicate, both sides;
 *   `file-event`      the Q11 watcher watches the picked report's own `.e`
 *                     path and feeds `save` with it, which clears
 *                     unconditionally for a `.e` file;
 *   `recovered`       the rerender effect exists only for an ACCEPTED
 *                     `{stuck:false}`, and the same acceptance clears;
 *   `roots`           **DOES NOT QUALIFY, AND WAS WRONGLY OUT.** The glue
 *                     schedules on `affectsConfiguration`, but `guardReduce`
 *                     clears only when the roots FINGERPRINT moved. A
 *                     setting edited to an equal resolved list therefore
 *                     rendered a held report. The justification recorded for
 *                     leaving it out proves the opposite: if the resolved
 *                     list is the render session's discard key and it did
 *                     not move, then nothing that matters changed, which is
 *                     precisely when the question must be asked. MEASURED by
 *                     the delta re-review's exhaustive explorer: adding it
 *                     removes 2,631 of 5,097 violating sequences.
 * And the ones that never qualified:
 *   `restart`         the Stopped -> Running re-render (WP-22 (b));
 *   `params-file`     a params file was saved or changed on disk. If the
 *                     fingerprint had moved, `guardReduce`'s `params` event
 *                     would already have CLEARED the mark and this cannot
 *                     refuse; reaching here with the mark still standing
 *                     means the bytes changed and the parameters did not --
 *                     a re-format, a format-on-save, a moved `$schema` line;
 *   `module-learned`  the module name arrived and the params file could be
 *                     found at last. Nothing about the report changed.
 * `explicit` is consent and is never refused.
 *
 * **AND AN UNKNOWN TRIGGER IS REFUSED, NOT PERMITTED (D2).** This function
 * used to fail OPEN on anything it did not recognise -- `undefined`, `null`,
 * `""`, a typo -- and a mutant that simply forgot to forward the trigger
 * through the coalescer therefore neutered BOTH consultation sites for every
 * automatic render and survived all 210 tests. A trigger outside the closed
 * `RENDER_TRIGGERS` is now treated as unconfirmed AND reported as a BUG by
 * `triggerProblem`, which the glue logs loudly -- the same philosophy as the
 * restart reducer's clockless arm: the defect it names costs a whole feature
 * silently. The cost of the new policy is one spurious question if anyone
 * ever adds a trigger and forgets to declare it; the cost of the old one was
 * the loop this ticket exists to close.
 */
const TRIGGER_EXPLICIT = "explicit";
const TRIGGER_PARAMS_FILE = "params-file";
const TRIGGER_MODULE_LEARNED = "module-learned";
const TRIGGER_INVALIDATED = "invalidated";
const TRIGGER_FILE_EVENT = "file-event";
const TRIGGER_ROOTS = "roots";
const TRIGGER_RECOVERED = "recovered";
/**
 * `applyStuck`'s third argument is a render trigger like any other -- it is
 * forwarded to `shouldAutoRender` -- and one of its three call sites passes
 * this. `stuckReduce` never emits `rerender` for an `answer` event (rule (3)
 * refuses one and a wedged one only raises), so it cannot reach the
 * consultation today; it is declared anyway, because "it happens not to
 * collide" is not a vocabulary (D2).
 *
 * **AND IT IS UNCONFIRMED, which costs nothing today and is the safe side of
 * the one way it could ever matter** (final re-check, nit 5): if
 * `stuckReduce` ever grew a rerender on an answer, that render would carry
 * no evidence that anything had changed -- an answer is the server
 * describing the render we just sent -- and a trigger kept out of the
 * refused set by a comment nobody re-reads is exactly how D1 happened.
 */
const TRIGGER_ANSWER = "answer";

/**
 * WP-8 S3: AN AUTOMATIC `ermine/schema` REQUEST THAT NOTHING ELSE ASKED FOR.
 *
 * **A SCHEMA REQUEST IS NOT A READ. IT CAN WEDGE THE SERVER, AND THAT IS
 * READ OFF THE SCALA RATHER THAN ASSUMED.**  `ermine/schema {uri, binding,
 * roots}` is a PREVIEW-QUEUE job (`lsp/Preview.scala:603-623`) answered by
 * `Runner.paramSchema` (`lsp/Preview.scala:1554-1567`), which calls
 * `report(module, binding)` -> `compileOnce`, and `compileOnce` runs
 * `Session.loadModules(List(module))` and then `Session.eval(binding, ...)`
 * (`json/Runner.scala:849-852`) under `evalLock`.  Loading type-checks the
 * module and evaluating forces the binding to WHNF.  `Preview.scala:596-598`
 * says it in the server's own words: *"THE WATCHDOG covers it: `paramSchema`
 * compiles the report, which evaluates the binding, which is the very thing
 * that can fail to terminate."*  So the schema job is watched, refused while
 * stuck, and can itself be the job the watchdog fires on -- exactly what
 * WP-22 exists to hold.
 *
 * WHICH TRIGGER A SCHEMA REQUEST CARRIES, all three sites:
 *   the FIRST-PICK request (no params file -> schema before the render, G15)
 *     carries THE RENDER'S OWN TRIGGER, because it is part of that render's
 *     work: an explicit pick is consent and is never refused, and a
 *     `params-file` save of a held report is refused exactly as its render
 *     would be;
 *   the `fx.schema` seam (an accepted `{stuck:false}`, and Stopped ->
 *     Running) carries `recovered` / `restart`, the triggers `applyStuck`
 *     already passes;
 *   the POST-RENDER REFRESH (D8) has no render trigger to inherit -- it is
 *     asked for by an answer -- and carries THIS one.
 *
 * **IT IS UNCONFIRMED, AND THE MEMBERSHIP RULE FORCES THAT.**  The rule is
 * "a trigger may stay OUT only if, whenever the glue schedules it, the guard
 * event it fed has CLEARED the mark".  The guard event a render's answer
 * feeds is `answer`, and `guardReduce`'s `answer` case KEEPS the mark for a
 * non-stuck answer (it only ever SETS, never clears).  So a refresh cannot
 * qualify, and it must not: a report that has just wedged the server must
 * not be handed another job that compiles and evaluates it.
 */
const TRIGGER_SCHEMA = "schema";

/** Every trigger the glue may pass. Anything else is a BUG, not a default. */
const RENDER_TRIGGERS = [
  TRIGGER_RESTART, TRIGGER_EXPLICIT, TRIGGER_PARAMS_FILE, TRIGGER_MODULE_LEARNED,
  TRIGGER_INVALIDATED, TRIGGER_FILE_EVENT, TRIGGER_ROOTS, TRIGGER_RECOVERED,
  TRIGGER_ANSWER, TRIGGER_SCHEMA,
];

/** The ones that bring no evidence of change, and therefore consult the mark. */
const UNCONFIRMED_TRIGGERS = [
  TRIGGER_RESTART, TRIGGER_PARAMS_FILE, TRIGGER_MODULE_LEARNED, TRIGGER_ROOTS, TRIGGER_ANSWER,
  TRIGGER_SCHEMA,
];

function isRenderTrigger(trigger) {
  return typeof trigger === "string" && RENDER_TRIGGERS.indexOf(trigger) >= 0;
}

/**
 * The BUG line for a trigger nothing declared, or null. The glue says it out
 * loud: a render that is silently held for ever is worse than a noisy line.
 */
function triggerProblem(trigger) {
  if (isRenderTrigger(trigger)) return null;
  return "a render was triggered by " + printable(typeof trigger === "string" ? trigger : typeName(trigger)) +
         ", which is not one of the declared render triggers (" + RENDER_TRIGGERS.join(", ") +
         "). It is treated as bringing no evidence of change, so a report that wedged is held " +
         "rather than re-rendered. Whoever added the trigger must declare it in preview-core.js.";
}

function shouldAutoRender(mark, pick, trigger) {
  // D2: unknown -> unconfirmed. Known-and-not-unconfirmed -> permitted.
  if (isRenderTrigger(trigger) && UNCONFIRMED_TRIGGERS.indexOf(trigger) < 0) return true;
  return !markMatches(mark, pick);
}

/**
 * WAS THE MARK MINTED AFTER THIS RENDER WAS SCHEDULED? (the delta
 * re-review's families B and C, and option (b) of its DOC must-fix.)
 *
 * The consultation above asks "does a mark stand?". That is not enough for a
 * render that was SCHEDULED on real evidence and then sat in the 150 ms
 * coalescing window and the params read while the report wedged AGAIN:
 * `invalidated` clears the mark and schedules, a `{stuck:true}` or a
 * `Stopped` edge re-mints one, and the render then fires with a mark
 * standing and a trigger that is not unconfirmed. MEASURED by the explorer:
 * 2,466 of the 5,097 violating sequences are exactly that.
 *
 * THE OUTCOME WAS DEFENSIBLE AND IS STILL NOT WHAT WE WANT. The evidence was
 * real when the render was scheduled -- but by the time it would be sent the
 * report has wedged the server again, and sending it is the one thing WP-22
 * exists to stop. The server would refuse it anyway while stuck; what the
 * developer wants there is the question, not a refusal in the tab.
 *
 * So a non-explicit render also asks when the mark is NEWER than the trigger
 * that scheduled it. `scheduledAt` comes from the glue (`scheduleRender`
 * takes `Date.now()` on every call).
 *
 * **WHAT IT DOES WHEN IT CANNOT COMPARE, corrected after the final re-check
 * found this comment claiming one thing while the code did another.** A mark
 * with no `at`, and a missing or non-numeric `scheduledAt`, answer FALSE --
 * fail OPEN, because this arm refines an already-safe decision. **A CLOCK
 * THAT MOVED BACKWARDS DOES NOT, and there is no check for one**: a mark
 * whose `at` then lies in the FUTURE of `scheduledAt` answers TRUE and the
 * render is HELD (MEASURED). That is the right trade -- it costs ONE
 * question on a machine whose clock jumped, against a wedge re-issued
 * silently -- but the sentence that used to stand here claimed the
 * opposite, so the behaviour is written down as what it is: fail CLOSED on
 * a backwards clock, fail OPEN on a missing value.
 *
 * MEASURED, and the reason no RESTORED mark can cause a spurious hold: a
 * mark read back from `workspaceState` carries the `at` of the session that
 * minted it, which is in the PAST of anything this session schedules, so it
 * answers FALSE.
 */
function markMintedAfter(mark, pick, scheduledAt) {
  if (!markMatches(mark, pick)) return false;
  if (typeof scheduledAt !== "number" || !isFinite(scheduledAt)) return false;
  if (typeof mark.at !== "number" || !isFinite(mark.at)) return false;
  return mark.at > scheduledAt;
}

/**
 * MAY THIS RENDER GO, ALL IN? (D1, D2 and families B/C in one answer.)
 *
 * The glue calls THIS, not the two halves, so that the second consultation
 * site cannot drift from the first, and so that a caller cannot ask one
 * question and forget the other.
 */
function mayAutoRender(mark, pick, trigger, scheduledAt) {
  if (trigger === TRIGGER_EXPLICIT) return { render: true, why: null };
  if (!shouldAutoRender(mark, pick, trigger)) {
    return { render: false, why: "nothing about " + pickLabel(pick) + " has changed since it wedged the preview" };
  }
  if (markMintedAfter(mark, pick, scheduledAt)) {
    return {
      render: false,
      why: pickLabel(pick) + " wedged the preview again AFTER this render was scheduled, so the " +
           "change that scheduled it is not evidence about the server it would now reach",
    };
  }
  return { render: true, why: null };
}

/**
 * D3: HOW A REFUSED QUESTION IS REMEMBERED, so that format-on-save does not
 * ask once per keystroke-and-save.
 *
 * The token is the MARK's identity plus the params it carries. A second
 * re-format of the same file, against the same mark, produces the same token
 * and is not asked about again; anything that changes the situation --
 * the mark cleared and re-minted (a new `at`), another pick, parameters that
 * really moved (which clears the mark anyway) -- produces a different token
 * and asks.
 */
function heldPromptToken(mark) {
  if (!isMark(mark)) return null;
  return String(mark.key) + MARK_SEPARATOR + String(mark.at) + MARK_SEPARATOR + String(mark.paramsFingerprint);
}

/**
 * Should the held question be shown again, given what was last refused?
 *
 * ONLY `params-file` IS REMEMBERED, and that is a decision with an argument.
 * A params save under a formatter can repeat every few seconds and is not a
 * new event; a RESTART is -- either the user pressed the button or the
 * server died again -- and WP-22 already answers one question per restart.
 * `module-learned` happens at most once per pick, and a `roots` edit is the
 * developer typing in a settings file. So those three always ask.
 */
function shouldAskHeld(lastRefusedToken, mark, pick, trigger) {
  const token = heldPromptToken(mark);
  if (token === null || !markMatches(mark, pick)) {
    return { ask: false, token: null, why: "there is no mark for this report to ask about" };
  }
  if (trigger !== TRIGGER_PARAMS_FILE) return { ask: true, token, why: null };
  if (lastRefusedToken !== token) return { ask: true, token, why: null };
  return {
    ask: false,
    token,
    why: 'this question was already answered "Not now" for these parameters; the preview stays held ' +
         "until they change or you render it yourself",
  };
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
 * `markPickFor`'s other half (WP-8 S2): the PARAMS the mark should carry.
 *
 * WP-22 put `paramsFingerprint` in the mark's VALUE so that changing the
 * parameters CLEARS the mark rather than minting a second one, and said
 * WP-8's job was to hand it the params actually sent. This is that hand-off:
 * the render that is in flight is the better claim about what wedged -- its
 * params are the ones the server is chewing on -- and the last params we sent
 * are the fallback when nothing is running.
 *
 * `null` IS A VALUE HERE, not "nothing": a params file holding `null` is what
 * a `Maybe`-rooted report wants. So the ABSENT case is `undefined` and only
 * `undefined`, and the call sites spell it `inFlightRender ? its params :
 * undefined` rather than with the `&&` idiom `markPickFor` takes, which would
 * collapse "no render is out" and "the render that is out sends null".
 */
function markParamsFor(inFlightParams, lastParams) {
  return inFlightParams === undefined ? lastParams : inFlightParams;
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
 * written through.  This function's answer is a candidate path, not a
 * permission.
 *
 * **WHAT S3 ACTUALLY DID, and the sentence that stood here was WRONG (the S3
 * review's M-3).**  It said "S3 resolves before it writes".  S3 does NOT
 * resolve -- there is no `realpath` anywhere in this extension, and
 * `workspace.fs` offers none.  What S3 does instead is REFUSE: before any
 * write it `stat`s every target and every existing directory component under
 * `.ermine/`, and `writeTargetProblem` below turns a `FileType.SymbolicLink`
 * bit into a named refusal, so the report renders with `{}` and nothing is
 * written through a link.  Refusing is strictly weaker than resolving -- a
 * legitimate symlinked `.ermine` directory stops working, and is told why --
 * and it is what a pure decision plus one `stat` can honestly do.  The first
 * cut of S3 did NEITHER, and the review MEASURED both halves: a
 * `<binding>.schema.json` symlinked outside the workspace was written
 * THROUGH from the REFRESH path (reachable from an answer), and a DANGLING
 * params symlink had the skeleton created at its outside target.
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
    // S2: THE SAME FILE, SPELLED AS A GLOB RELATIVE TO THE WORKSPACE FOLDER.
    // `createFileSystemWatcher` takes a `RelativePattern(folder, pattern)`,
    // and a pattern is forward-slashed on every platform (*external*: VS
    // Code's glob syntax, which is not a path). Watching the folder with
    // this pattern rather than the params DIRECTORY with a file name is
    // what makes a file whose directory DOES NOT EXIST YET still reported
    // when it appears -- the `.ermine/preview/<Module>/` tree is not there
    // until S3 (or the developer) writes it.
    relativeGlob: PREVIEW_SEGMENTS.concat([moduleName, paramsName]).join("/"),
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

// ------------------------------------------------- params files (WP-8, S2)
//
// S2 SENDS THE FILE.  S1 decided WHERE a params file lives and WHAT its text
// turns into; S2 is the glue's half -- read it off the disk at SEND time,
// send it, and re-render when it changes -- and everything in it that can be
// a decision about data is here rather than in `src/extension.js`.
//
// S2 WRITES NOTHING.  No skeleton, no `.schema.json`, no `.gitignore`, and
// no `ermine/schema` request: those are S3.  A params file exists here only
// because a developer wrote one and committed it.
//
// THE THREE DECISIONS S2 ADDS, and why each is here and not there:
//   1. WHICH WORKSPACE FOLDER owns the report (`paramsFolderFor`).  Section 6
//      says "the workspace folder of the picked report", and `rootsFor`'s
//      fallback to `folders[0]` is exactly what review G1 refuses for a file
//      on disk -- `folders[0]` would mint `.ermine/` in an unrelated repo.
//   2. WHETHER A FAILED READ MEANS THE FILE IS NOT THERE (`meansFileMissing`).
//      "Not there" is the ordinary case and renders with `{}`; anything else
//      is a file we could not read, which is a refusal for S1's own reason:
//      rendering `{}` over parameters that exist shows a document that looks
//      right and is not.
//   3. WHETHER THIS RENDER MAY STILL BE SENT AFTER THE READ (`mayStillSend`).
//      This is the one S2 exists to get right; see its comment.

/**
 * WHICH WORKSPACE FOLDER OWNS THIS REPORT (review G1, multi-root).
 *
 * NEVER `folders[0]`.  `rootsFor` falls back to the first folder for a file
 * outside every folder, and for a SETTING that is defensible -- a window-scope
 * value has to come from somewhere.  For a FILE ON DISK it is not: it would
 * write `.ermine/preview/<Module>/` into whichever repository happens to be
 * first in the window.  A report outside every folder gets no params file at
 * all, which `paramsPaths` then names `no-workspace-folder`.
 *
 * THE INNERMOST CONTAINING FOLDER WINS.  VS Code permits a folder nested
 * inside another in one window (*external*, documented as allowed), and the
 * params file belongs to the folder the developer actually opened the report
 * from -- the deeper one, whose `.ermine/preview` is the one beside it.
 * `getWorkspaceFolder` is documented to answer the same way; this function
 * exists so the answer is testable without an editor, and so that the code
 * that WRITES paths and the code that DECIDES containment use one rule
 * (`isInsideFolder`, a prefix compare on normalised absolute paths).
 *
 * @param {string} fsPath the picked report's absolute path
 * @param {string[]} folderPaths every workspace folder's absolute path
 * @returns {string|null} the folder, or null when the report is in none
 */
function paramsFolderFor(fsPath, folderPaths, flavour) {
  const p = pathFlavour(flavour);
  if (typeof fsPath !== "string" || !fsPath) return null;
  let best = null;
  let bestLength = -1;
  for (const folder of Array.isArray(folderPaths) ? folderPaths : []) {
    if (typeof folder !== "string" || !folder) continue;
    if (!isInsideFolder(p, folder, fsPath)) continue;
    const length = comparablePath(p, folder).length;
    if (length > bestLength) {
      best = folder;
      bestLength = length;
    }
  }
  return best;
}

/**
 * DOES THIS READ FAILURE MEAN "THERE IS NO SUCH FILE"?
 *
 * The ordinary case -- no params file -- must render with `{}` exactly as
 * WP-7 does today, and every OTHER failure (a permission, a directory where
 * a file should be, a filesystem that went away) must NOT, because rendering
 * `{}` over parameters that exist but could not be read is precisely the
 * silent-wrong-document failure S1 refused an empty file for.
 *
 * THE CODES, and where each comes from: `FileNotFound` is
 * `vscode.FileSystemError.FileNotFound`'s `code` (*external*, VS Code's own
 * documented shape, UNVERIFIED here -- nobody has run this extension);
 * `ENOENT` and `ENOTDIR` are node's, which is what a fallback read or a test
 * double produces. `ENOTDIR` counts as missing on purpose: a params
 * directory that is a FILE means the path does not exist as a file either,
 * and the developer sees `git status` rather than a preview refusal --
 * **and `FileNotADirectory` is VS Code's spelling of that same physical
 * state** (S2 review nit 1: without it the same situation classified
 * differently depending on which filesystem provider answered).
 * `FileIsADirectory` / `EISDIR` is deliberately NOT here: something IS at
 * that path, and `{}` would hide it.
 * Anything else -- including an error with no code at all -- is NOT missing,
 * which is the direction that refuses rather than renders.
 *
 * THE `name` FALLBACK IS A SUBSTRING TEST (review nit 2): VS Code has been
 * seen to render `name` as `"EntryNotFound (FileSystemError)"`, which an
 * exact match would miss. `code` is still the primary test, so this only
 * matters when there is no code at all.
 */
const MISSING_FILE_CODES = [
  "FileNotFound", "FileNotADirectory", "ENOENT", "ENOTDIR", "EntryNotFound",
];

function meansFileMissing(err) {
  if (!err) return false;
  const code = err.code !== undefined && err.code !== null ? String(err.code) : null;
  if (code && MISSING_FILE_CODES.indexOf(code) >= 0) return true;
  const name = typeof err.name === "string" ? err.name : null;
  if (!name) return false;
  return MISSING_FILE_CODES.some((known) => name.indexOf(known) >= 0);
}

/**
 * THE CAP, APPLIED BEFORE THE FILE IS MATERIALISED (review nit 3).
 *
 * `paramsToSend` caps the TEXT, which means `workspace.fs.readFile` has
 * already pulled the whole file into the extension host: the cap's own
 * comment reasons about a 64 MiB frame killing the SERVER, and a 1 GiB
 * params file kills the HOST the same way. So the glue `stat`s first and
 * asks this; the text cap stays as the authority (a file that grows between
 * the stat and the read is still refused, and a provider that cannot stat is
 * simply read).
 *
 * A stat that ANSWERS NOTHING USEFUL -- no size, a negative, a NaN -- reads
 * as "carry on and let the text cap decide", because refusing on a stat we
 * could not understand would refuse every provider that does not implement
 * it.
 */
function paramsTooLargeToRead(size, maxBytes) {
  const cap = typeof maxBytes === "number" && maxBytes > 0 ? maxBytes : PARAMS_MAX_BYTES;
  if (typeof size !== "number" || !isFinite(size) || size < 0) return null;
  if (size <= cap) return null;
  return problem("too-large",
                 "The params file is " + size + " bytes and the preview sends at most " + cap +
                 " bytes of parameters, so it was not read and the report was not rendered.").problem;
}

/** How long the params read may take before the render gives up (review nit 7). */
const PARAMS_READ_TIMEOUT_MS = 5000;

/**
 * A READ THAT NEVER SETTLES IS NOT A READ THAT THREW (review nit 7, and it
 * is `stopQuietly`'s own lesson from the WP-22 (c) review: "it also hangs,
 * and a hang is not a throw"). A `readFile` on a dead remote provider would
 * otherwise leave the spinner on "rendering" for the life of the window,
 * because everything that releases it is after the await.
 */
function paramsReadTimedOut(paramsPath, ms) {
  return problem("timed-out",
                 "The params file " + printable(paramsPath) + " did not finish being read within " +
                 Math.round((typeof ms === "number" ? ms : PARAMS_READ_TIMEOUT_MS) / 1000) +
                 "s, so the report was not rendered. Save it again to retry.").problem;
}

/** The reasons `mayStillSend` can refuse with, closed and in its own order. */
const ABANDON_REASONS = [
  "pick-cleared", "pick-changed", "roots-changed", "superseded",
  "server-restarted", "server-stopped", "no-client",
];

/**
 * THE SNAPSHOT A RENDER IS DECIDED ON, taken BEFORE the read, and the only
 * thing the rest of `renderNow` is allowed to read.
 *
 * **IT IS A SNAPSHOT AND NOT A VIEW, AND THAT IS THE S2 REVIEW'S M1.**  The
 * first cut captured `const sentPick = picked` -- a REFERENCE -- while the
 * roots handler MUTATES `picked.roots` IN PLACE.  `mayStillSend` then
 * compared an array with itself and the `roots-changed` arm could not fire
 * in the real glue at all (MEASURED: `{"send":true}` where the model, which
 * REPLACED the pick object, answered `roots-changed`).  The render went out
 * carrying the NEW roots under the OLD generation -- booting a render
 * session the 150 ms-later render boots again.  So the pick is COPIED here,
 * its roots array included, and the copy is frozen.
 *
 * IT IS ALSO WHAT MAKES THE GAP CHECK HARD TO NEUTER (review M2).  Four
 * mutants survived the whole suite by swapping one captured value for the
 * live global in an object literal written AFTER the await
 * (`clientEpoch: sentEpoch` -> `clientEpoch`, `pick: sentPick` -> `picked`,
 * `generation: mine` -> `generation`, and the request builder taking
 * `picked`).  There is no such literal any more: everything after the await
 * reads this object, which was built BEFORE it, where reading a live global
 * is not merely allowed but correct.
 *
 * @param {number} generation this render's own counter
 * @param {object} pick the current pick, copied
 * @param {number} clientEpoch the epoch of the client this render belongs to
 * @param {number} stopCount how many times the client has been seen to stop
 * @param {number} seqAtSend `stuckState.highWater` at send (rule (1)/(3))
 */
function renderAttempt(generation, pick, clientEpoch, stopCount, seqAtSend) {
  const copied = pick && typeof pick === "object"
    ? Object.freeze(makePick(pick.uri, pick.fsPath, pick.binding, pick.module, pick.roots))
    : null;
  if (copied) Object.freeze(copied.roots);
  return Object.freeze({
    generation: generation,
    pick: copied,
    clientEpoch: clientEpoch,
    stopCount: stopCount,
    seqAtSend: seqAtSend,
    key: markKey(copied),
    label: pickLabel(copied),
  });
}

/**
 * The live state `mayStillSend` compares the snapshot against: the module
 * globals, read at the moment of the comparison and nowhere else.
 */
function previewNow(generation, pick, clientEpoch, stopCount, hasClient) {
  return {
    generation: generation,
    pick: pick,
    clientEpoch: clientEpoch,
    stopCount: stopCount,
    hasClient: hasClient === true,
  };
}

/**
 * The `ermine/render` request for an ATTEMPT, so that the pick and the
 * generation on the wire cannot come from anywhere but the snapshot (review
 * M2's R9 and R10, which swapped each for a live global and survived).
 */
function renderRequest(attempt, params) {
  return renderParams(attempt.pick, params, attempt.generation);
}

/**
 * AFTER THE READ, MAY THIS RENDER STILL BE SENT?
 *
 * THIS IS THE FUNCTION S2 EXISTS TO GET RIGHT.  Reading the params file puts
 * an `await` between "we decided to render THIS pick" and "we send it", and a
 * decision applied to state that moved under it is the defect this code base
 * has already been bitten by three times: WP-22's M1 (the mark depended on
 * which of two events the library delivered first), M2 (a restart inside the
 * classpath warm-up left two clients), and the final re-check's timed-out
 * stop (an edge dropped as stale by the very guard that fixed M2).  So the
 * decision is a function of two snapshots rather than a pile of `if`s in the
 * middle of an async function, and the test file drives the interleavings.
 *
 * WHAT MOVES, AND WHAT EACH MEANS:
 *   `pick-cleared`     nothing is picked any more (a teardown);
 *   `pick-changed`     the user picked another report while we were reading:
 *                      the params we just read are the OLD report's, and
 *                      sending them is the wrong-params-for-the-wrong-pick
 *                      failure in its purest form;
 *   `roots-changed`    `ermine.preview.roots` moved. The root set is the
 *                      render session's discard key (section 2.4), so this
 *                      request would boot a session the next one throws away;
 *   `superseded`       a NEWER render started while we read. Its answer is
 *                      the one the tab wants, and this one's would be
 *                      discarded by the generation check anyway -- but only
 *                      after it had cost a render on the server;
 *   `server-restarted` the client was replaced (a crash, the Restart button,
 *                      WP-22 (c)'s own timer). The fresh server has not been
 *                      consulted about the wedge mark, and a request slipped
 *                      into it here would reach it WITHOUT passing WP-22's one
 *                      consultation site -- the same hole `fireRestart` clears
 *                      the coalesced render for;
 *   `server-stopped`   the client STOPPED and came back without being
 *                      replaced. A DEFENCE AGAINST UNVERIFIED LIBRARY
 *                      BEHAVIOUR (review M5): `clientEpoch` moves only inside
 *                      our own `startClient`, and `vscode-languageclient` is
 *                      configured with no `errorHandler` and no
 *                      `maxRestartCount`, so its default close action may
 *                      restart the server process on the SAME client object.
 *                      Its source is unread (project rule) and nobody has run
 *                      this extension, so this is not measured -- but the
 *                      counter costs one integer and the hole it would leave
 *                      is the exact one `server-restarted` exists to close;
 *   `no-client`        there is nothing to send with.
 *
 * THE ORDER IS MOST-SPECIFIC-FIRST, because the reason is what the channel
 * prints: a pick change also bumps the generation (picking renders), so
 * testing the generation first would report every pick change as
 * "superseded" and tell the reader nothing.
 *
 * IT IS DELIBERATELY NOT THE CALLER'S JOB TO RE-CHECK ANY OF THIS: the glue
 * calls it once, and the ONE thing it may add is a null check on the client
 * handle it is about to use.
 *
 * @param {{generation, pick, clientEpoch}} atSend the snapshot taken BEFORE the read
 * @param {{generation, pick, clientEpoch, hasClient}} now the snapshot after it
 */
function mayStillSend(atSend, now) {
  const refuse = (reason, why) => ({ send: false, reason, why });
  if (!atSend || typeof atSend !== "object" || !now || typeof now !== "object") {
    return refuse("pick-cleared", "there is no render to send");
  }
  const wasKey = markKey(atSend.pick);
  const isKey = markKey(now.pick);
  if (wasKey === null || isKey === null) {
    return refuse("pick-cleared", "no report is picked any more");
  }
  if (wasKey !== isKey) {
    return refuse("pick-changed",
                  "the pick changed to " + pickLabel(now.pick) + " while the parameters were being read");
  }
  if (rootsFingerprint(atSend.pick && atSend.pick.roots) !== rootsFingerprint(now.pick && now.pick.roots)) {
    return refuse("roots-changed", "ermine.preview.roots changed while the parameters were being read");
  }
  if (atSend.generation !== now.generation) {
    return refuse("superseded",
                  "render " + printable(now.generation) + " started while the parameters were being read");
  }
  if (atSend.clientEpoch !== now.clientEpoch) {
    return refuse("server-restarted", "the language server was restarted while the parameters were being read");
  }
  if (atSend.stopCount !== now.stopCount) {
    return refuse("server-stopped", "the language server stopped while the parameters were being read");
  }
  if (now.hasClient === false) {
    return refuse("no-client", "the language client went away while the parameters were being read");
  }
  return { send: true, reason: null, why: null };
}

/**
 * A PARAMS REFUSAL, DRESSED AS AN ANSWER so the tab shows it the way it shows
 * every other failure (`tabContent` -> the whole `{ok:false, ...}` object).
 *
 * `status` IS NULL AND THAT IS THE POINT: no server was asked, so there is no
 * HTTP-shaped status to quote, and a reader can tell this refusal from a 400
 * by that alone. The named reason travels under `paramsProblem` rather than
 * under `reason`, because `reason` is the SERVER's closed vocabulary on this
 * wire (section 4, Q15) and `isPlacement404` switches on it; minting a
 * client-side value into it would make a preview refusal indistinguishable
 * from a placement one for any code written later.
 *
 * `path` IS THE PARAMS FILE, not a JSON path. On a server refusal `path` is
 * where in the REQUEST the fault is; here the fault is a file, and its path is
 * the one thing the developer needs in order to act.
 */
function paramsRefusalAnswer(problem, paramsPath, generation) {
  const p = problem && problem.problem ? problem.problem : problem;
  return {
    ok: false,
    status: null,
    message: (p && p.message ? String(p.message) : "the params file could not be used") +
             " Nothing was sent to the language server.",
    path: typeof paramsPath === "string" ? paramsPath : null,
    paramsProblem: p && p.reason ? String(p.reason) : "unknown",
    generation: generation,
  };
}

/**
 * The key under which the glue remembers that it has already said something
 * about this pick's params, so "one line per distinct problem per pick" is
 * once and not once per render. Pure so that the rule is testable and so that
 * two notices about different picks can never collide.
 */
function paramsNoticeKey(pick, reason) {
  return String(markKey(pick)) + MARK_SEPARATOR + String(reason);
}

/** The sentence for "there is no params file here", said once per pick. */
function paramsMissingNotice(paramsPath) {
  return "no params file at " + printable(paramsPath) +
         " -- rendering with empty parameters. Write one there (it is ordinary committed source) " +
         "to give this report its parameters.";
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

// -- WP-8 S3: asking for the schema, and what gets written -----------------
//
// S1 decided WHERE the files go and WHAT their text is; S2 reads the params
// file and sends it.  S3 is the first `ermine/schema` client and the first
// thing in this extension that WRITES to the developer's disk.  Everything
// below is the part of that which is decidable from data alone: the
// ordering rule, when a schema answer may be used, what a schema answer
// turned out to be, which bytes go to which path, and whether a file that is
// already there has to be touched at all.  The `vscode.workspace.fs` calls,
// the `WorkspaceEdit` and the document that is opened are `extension.js`'s.

/**
 * `YYYY-MM-DD` in the machine's own timezone, for `skeletonFrom`'s `today`.
 *
 * LOCAL AND NOT UTC, and the reason the first draft gave was too strong (the
 * S3 review's N-8): "west of Greenwich the slice is tomorrow's for most of
 * the working day" is only true of the FAR west.  At UTC-4 an ISO-UTC slice
 * flips at 20:00 local; at UTC+13 it is YESTERDAY's until 11:00.  Either way
 * it is a date the developer did not mean, and `toISOString().slice(0,10)`
 * is the obvious thing to reach for, so the choice is written down.
 *
 * **AND THE QUESTION IS MOOT, WHICH NOBODY HAD WRITTEN DOWN** (the review's
 * own point, kept): the language server is the LOCAL `bin/ermine-lsp`,
 * sharing this machine's default timezone, and this feature has no
 * server-side "today" at all -- U2's row forbids computed defaults, so a
 * rolling range has to be literal JSON in the params file.  There is no
 * second clock for this one to disagree with.
 *
 * A pure function of the `Date` it is handed, so the glue owns the clock
 * exactly as it does for the restart reducer.
 */
function isoDay(when) {
  const d = when instanceof Date ? when : new Date(when);
  if (isNaN(d.getTime())) return null;
  const pad = (n) => (n < 10 ? "0" + n : String(n));
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

/**
 * G15, THE ORDERING RULE, DECIDED PER CASE.
 *
 *   NO params file  -> THE SCHEMA COMES FIRST.  That render would be sent
 *                      with `{}` and is a CERTAIN 400 for any report with a
 *                      required parameter (MEASURED, section 6's control E:
 *                      `400 the required key "fromDay" is missing`), so
 *                      spending it is spending a boot to be told what we are
 *                      about to ask the schema for.  The schema, the write
 *                      and then ONE render -- the one the skeleton's own
 *                      creation schedules through the S2 watcher.
 *   FILE PRESENT    -> THE RENDER COMES FIRST.  The parameters are on disk
 *                      and the developer is waiting for a document; the
 *                      schema is only needed to keep the generated
 *                      `<binding>.schema.json` fresh, which is D8's
 *                      write-if-different and can follow the answer.
 *   NO PATHS AT ALL -> neither.  A report outside every workspace folder, a
 *                      pick with no module, an operator binding: there is
 *                      nowhere to write and nothing to describe, so the
 *                      render goes with the inline `{}` exactly as S2 sends
 *                      it today, and S2 has ALREADY said why, once per pick.
 *
 * @param {object} paths `paramsPaths`'s answer (or its `{problem}`)
 * @param {boolean} fileMissing did the read report "there is no such file"?
 */
function schemaOrder(paths, fileMissing) {
  if (!paths || typeof paths !== "object" || paths.problem || !paths.paramsPath) {
    return { first: "render", write: false,
             why: "this report has no params path, so nothing is written and no schema is asked for" };
  }
  if (fileMissing === true) {
    return { first: "schema", write: true,
             why: "there is no params file yet, so the schema comes first and the skeleton is written from it" };
  }
  return { first: "render", write: false,
           why: "the params file is already on disk, so the render goes first and the schema only refreshes " +
                paths.schemaPath };
}

/**
 * THE RENDER TRIGGERS AFTER WHICH THE REPORT'S PARAMETER TYPE MAY HAVE MOVED.
 *
 * A schema request is a preview-queue JOB that compiles and evaluates the
 * binding (see `TRIGGER_SCHEMA`), so "ask after every render" is not free.
 * These five are the ones where the SOURCE or the ROOT SET can have changed
 * since the file was last written.  The four that are left out are left out
 * for a reason each:
 *   `params-file`   editing the parameters cannot change the parameter TYPE.
 *                   It is also the trigger the skeleton's own creation fires,
 *                   so leaving it out is what stops a first pick asking for
 *                   the schema twice in a row;
 *   `restart`       the `fx.schema` seam already asks on that edge;
 *   `recovered`     the same;
 *   `explicit`      is IN, because the user asking for a render is also the
 *                   moment to make the file they are looking at right.
 */
const SCHEMA_REFRESH_TRIGGERS = [
  TRIGGER_EXPLICIT, TRIGGER_INVALIDATED, TRIGGER_MODULE_LEARNED, TRIGGER_ROOTS, TRIGGER_FILE_EVENT,
];

/**
 * D8: AFTER A RENDER, IS THE GENERATED `.schema.json` WORTH RE-ASKING FOR?
 *
 * The ticket as written regenerated it on every `invalidated` that named the
 * report's module -- a disk write AND a queued preview job on every save of
 * the report or of anything it imports.  D8 narrows it to the two answers
 * that say the report COMPILED and its parameter type is therefore the thing
 * the file should describe:
 *
 *   `ok`                     the report ran: the type is current;
 *   `400` at `$.params...`   the decoder refused the parameters, which means
 *                            the report compiled and its `paramTy` exists --
 *                            and it is the one moment the developer is
 *                            looking at the file and wants its squiggles
 *                            right.
 *
 * Everything else says NO, and each for its own reason: a 404 or a 409 never
 * reached a report; a 500 is a load or an evaluation failure, so there may be
 * no parameter type to export and asking would only queue a job behind a
 * server that is already unhappy; a 400 anywhere but `$.params` is about the
 * request rather than the parameters; and a params REFUSAL (`status: null`,
 * S2's `paramsRefusalAnswer`) never asked a server anything at all.
 *
 * **WHAT THAT LEAVES ON DISK, AND IT IS DELIBERATE** (the S3 review's N-7).
 * A report that stops compiling -- or a schema request that comes back
 * `{error}` -- leaves the LAST GOOD `<binding>.schema.json` exactly where it
 * is.  Nothing deletes it and nothing marks it stale.  That is the useful
 * answer: while the developer is fixing the module, the editor keeps
 * completing and validating the params file against the type it last knew,
 * which is almost always still the type they are working towards; and the
 * alternative -- deleting it -- would take the squiggles away at the one
 * moment they are looking at them.  The file is generated and gitignored, so
 * a stale one costs nothing but its own bytes, and the next answer that
 * compiles rewrites it.
 *
 * AND THE TRIGGER DECIDES TOO, which D8 as written did not say: see
 * `SCHEMA_REFRESH_TRIGGERS`.  An undeclared trigger refreshes NOTHING, the
 * same fail-closed policy `shouldAutoRender` adopted for D2.
 */
function shouldRefreshSchema(answer, trigger) {
  if (!answer || typeof answer !== "object") {
    return { refresh: false, why: "there is no answer to decide on" };
  }
  if (SCHEMA_REFRESH_TRIGGERS.indexOf(trigger) < 0) {
    return { refresh: false,
             why: "a render triggered by " + printable(typeof trigger === "string" ? trigger : typeName(trigger)) +
                  " cannot have changed the report's parameter type" };
  }
  if (isOk(answer)) return { refresh: true, why: "the report rendered, so its parameter type is current" };
  if (answer.status === 400 && typeof answer.path === "string" &&
      (answer.path === "$." + "params" || answer.path.indexOf("$.params") === 0)) {
    return { refresh: true,
             why: "the parameters were refused at " + printable(answer.path) +
                  ", so the report compiled and the schema file should match what refused them" };
  }
  return { refresh: false,
           why: "the answer is not an ok and not a 400 about the parameters (" +
                printable(answer.status) + "), so there may be no parameter type to export" };
}

/**
 * **THE ONE SHAPE A SCHEMA REQUEST ANSWERS, MINTED IN ONE PLACE (the delta
 * re-review's D-1).**
 *
 * The first cut minted the SUCCESS arm and the three SERVER-SIDE failures
 * here as `{schema}` and a BARE `{reason, message}`, while the glue's other
 * two failure returns were WRAPPED `{problem: ...}`.  Both callers test
 * `outcome.problem`, which is `undefined` for a bare shape -- **so every
 * server-side failure fell straight through the handler.**  MEASURED on a
 * real disk with a stub client, for all three: the D8 refresh then reached
 * `schemaFileText(schemaFileFor(undefined))` and wrote the literal text
 * `undefined\n` into `<binding>.schema.json`, destroying the editor's
 * validation target; and on the first-pick path the named reasons became
 * dead code and the per-reason notice said NOTHING at all.  It is reachable
 * from an ANSWER, which is the one thing section 6 says an answer can never
 * do.
 *
 * So every arm goes through this, and **all three keys are always present**:
 * `if (outcome.problem)` cannot read `undefined` off a shape that forgot to
 * declare itself, and a builder call that names none of the three FAILS
 * CLOSED into a problem rather than into a silent success.
 */
function schemaOutcome(over) {
  const o = over && typeof over === "object" ? over : {};
  const out = { schema: null, problem: null, abandoned: null };
  if (o.abandoned !== undefined && o.abandoned !== null) {
    out.abandoned = o.abandoned;
    return out;
  }
  if (o.problem !== undefined && o.problem !== null) {
    out.problem = o.problem && o.problem.problem ? o.problem.problem : o.problem;
    return out;
  }
  if (isPlainObject(o.schema)) {
    out.schema = o.schema;
    return out;
  }
  out.problem = problem("no-schema",
                        "The parameter schema could not be worked out (" +
                        printable(typeName(o.schema)) + "), so nothing was written.").problem;
  return out;
}

/**
 * WHAT AN `ermine/schema` ANSWER TURNED OUT TO BE.
 *
 * The wire shape is the REQUEST's and not the reason's (`Preview.scala`'s
 * `schemaError`, `:2195-2197`): a failure is `{error}`, with Q15's `reason`
 * beside it when the shared front half decided it, and Q8's `stuck: true`
 * beside it when the preview is wedged and refused the job without queueing
 * (`Preview.Schema.stuckRefusal`, `Preview.scala:2354-2358`).  A success is
 * the exported schema document itself.
 *
 * NONE OF THESE MAY BLOCK THE RENDER.  Each answers a `{problem}` with a
 * named reason, the caller falls back to the inline `{}` and says so ONCE,
 * and the render happens anyway -- a params file is a convenience, and a
 * schema is a convenience for the params file.  **AND NONE OF THEM MAY
 * TOUCH THE SCHEMA FILE**, which is what D-1 was.
 */
function schemaAnswerOutcome(answer) {
  if (!isPlainObject(answer)) {
    return schemaOutcome({ problem: problem("no-schema",
      "The language server answered " + printable(typeName(answer)) +
      " to ermine/schema, not a schema document.") });
  }
  if (answer.error !== undefined && answer.error !== null) {
    const why = typeof answer.error === "string" ? answer.error : stringify(answer.error);
    if (answer.stuck === true) {
      return schemaOutcome({ problem: problem("stuck",
        "The preview is stuck, so it refused to work out the parameter schema (" + why +
        "). Nothing was written.") });
    }
    return schemaOutcome({ problem: problem("error",
      "The language server could not work out the parameter schema: " + why) });
  }
  return schemaOutcome({ schema: answer });
}

/** A JSON-RPC error or a transport rejection, in the SAME shape, so both
  * failures leave the caller with one thing to say -- and one thing to TEST,
  * which is what D-1 turned on. */
function schemaRequestFailure(err) {
  return schemaOutcome({ problem: problem("request-failed",
    "The ermine/schema request failed (" +
    (err && err.message ? String(err.message) : String(err)) +
    "), so no schema file was written.") });
}

/**
 * **DEFENCE IN DEPTH AT THE WRITE (D-1's second half): the bytes of a schema
 * file, or a named refusal -- a write of `"undefined"` must be impossible by
 * CONSTRUCTION, not only by control flow.**
 *
 * `schemaFileFor` answers its input unchanged when handed something that is
 * not a plain object, and `schemaFileText` is `JSON.stringify` plus a
 * newline -- which for `undefined` is the six-letter word.  That is exactly
 * what reached the disk.  Nothing but this function may produce the bytes of
 * a `<binding>.schema.json`, and it refuses anything that does not round-trip
 * to a JSON object.
 *
 * `schemaFileText` itself is NOT narrowed, deliberately: it also renders the
 * PARAMS file, whose value may legitimately be a number, a string or `null`
 * (G5's non-object roots, MEASURED on `WpInt`).
 */
function schemaFileBytes(schema) {
  if (!isPlainObject(schema)) {
    return problem("not-a-schema",
                   "The parameter schema the server answered is not a JSON object (" +
                   printable(typeName(schema)) + "), so no schema file was written.");
  }
  const text = schemaFileText(schemaFileFor(schema));
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    parsed = null;
  }
  if (typeof text !== "string" || !isPlainObject(parsed)) {
    return problem("not-a-schema",
                   "The parameter schema did not render to a JSON object, so no schema file was " +
                   "written; the file that was there is left alone.");
  }
  return { text: text };
}

/**
 * MAY THIS SCHEMA ANSWER STILL BE ACTED ON? (D7, and S2's own gap check.)
 *
 * `ermine/schema` carries NO generation and NO pick identity, so a late
 * answer cannot be recognised as late by the answer alone -- which is
 * exactly D7.  The glue therefore captures `core.renderAttempt`'s frozen
 * snapshot BEFORE the await (the SAME snapshot discipline S2 built for the
 * params read; no second style is invented) and asks this afterwards.
 *
 * IT IS BOTH TESTS, AND NEITHER IS REDUNDANT.  `mayStillSend` knows about
 * the restart, the stop counter, the generation and the teardown, but its
 * pick identity is `markKey`'s -- uri and binding.  `isCurrentSchemaAnswer`
 * knows about the MODULE (which is the DIRECTORY the file would be written
 * into) and about the roots in order.  A header edited from `module Sales`
 * to `module Sales2` moves the second and not the first.
 */
function mayUseSchemaAnswer(atSend, now, pickNow) {
  const verdict = mayStillSend(atSend, now);
  if (!verdict.send) return verdict;
  if (!isCurrentSchemaAnswer(atSend && atSend.pick, pickNow)) {
    return {
      send: false,
      reason: "pick-changed",
      why: "the report's module or roots moved while the parameter schema was being worked out, so the " +
           "answer describes a different file from the one it would be written beside",
    };
  }
  return { send: true, reason: null, why: null };
}

/**
 * D8's WRITE-IF-DIFFERENT, as a decision rather than as an `if` in the glue.
 *
 * The generated `<binding>.schema.json` is re-derived after every render
 * that compiled, which is every save of the report module in a save-driven
 * loop.  Writing identical bytes each time churns `git status`, re-triggers
 * every file watcher in the window and -- the reason it matters here -- can
 * make the editor drop and rebuild its cached schema while the developer is
 * typing against it.  `schemaFileText` exists precisely so that the same
 * schema always renders to the same bytes, which is what makes this
 * comparison meaningful.
 *
 * A file that could not be read compares UNEQUAL and is written: "we do not
 * know what is there" is not "it is already right".
 */
function schemaFileNeedsWrite(existingText, nextText) {
  if (typeof nextText !== "string") return false;
  if (typeof existingText !== "string") return true;
  return existingText !== nextText;
}

/**
 * THE BYTES, THE PATHS AND THE ORDER, for a first pick that has no params
 * file.  One pure answer, so the glue's write loop has no decisions left in
 * it and the whole plan can be asserted in a table test.
 *
 * **THE ORDER IS THE POINT AND IT IS NOT ALPHABETICAL.**  The params file is
 * LAST because its creation is what the S2 watcher sees (`relativeGlob` is
 * the exact params path, so neither the schema file nor the generated
 * `.gitignore` matches anything and neither triggers a render).  Writing it
 * first would schedule a render that then raced the schema file it is
 * supposed to be validated against.
 *
 * **`ifAbsent` vs `ifDifferent` IS THE WHOLE SAFETY STORY.**
 *   the generated `.gitignore`  `ifAbsent`: it is OURS to create and the
 *                               developer's to edit afterwards.  A file that
 *                               is there is never rewritten, whatever it
 *                               says;
 *   `<binding>.schema.json`     `ifDifferent`: it is generated, it is
 *                               gitignored, and it is rewritten whenever the
 *                               parameter type moves -- but never with the
 *                               bytes it already holds (D8);
 *   `<binding>.params.json`     `ifAbsent`, and NEVER ANYTHING ELSE.  It is
 *                               committed source.  U3's explicit command is
 *                               the only thing that may ever overwrite one,
 *                               and it is not built here.
 *
 * A NON-OBJECT PARAMS ROOT (G5, `embeddable: false`) still gets its params
 * file -- a bare number, a bare string -- but WITHOUT a `$schema` key,
 * because a JSON number has nowhere to put one.  The schema FILE is still
 * written: it is generated and ignored either way, the refresh path does not
 * have to learn a second rule, and a developer who wants it can point at it
 * by hand.  The notice says the editor will not validate that file.
 *
 * @param {object} paths `paramsPaths`'s answer (must not be a `{problem}`)
 * @param {object} schema the server's FRESH `ermine/schema` answer
 * @param {string} today `YYYY-MM-DD`
 */
function paramsWritePlan(paths, schema, today) {
  return writePlanWith(paths, schema, today, WRITE_IF_ABSENT);
}

/**
 * **S4: THE SAME PLAN, WITH THE PARAMS FILE'S MODE AS AN ARGUMENT, AND ONLY
 * U3's EXPLICIT COMMAND MAY ASK FOR THE OVERWRITE ONE.**
 *
 * The two plans must be byte-identical apart from that one mode, or the
 * command would write a different skeleton from the one a first pick writes
 * -- which nobody would notice until a developer compared two checkouts. So
 * there is ONE body and two entry points, and the mode is the only thing
 * that moves.
 *
 * `replace` is a STRICT `true`, the same discipline `schemaOrder`'s
 * `fileMissing` has: an "I do not know" must never be read as "the user
 * confirmed an overwrite". And the mode alone is not authority either --
 * `writeStep` refuses `explicitOverwrite` unless its caller ALSO passes the
 * permission, so a plan that leaks out of this function writes nothing.
 */
function skeletonCommandPlan(paths, schema, today, replace) {
  return writePlanWith(paths, schema, today, replace === true ? WRITE_EXPLICIT_OVERWRITE : WRITE_IF_ABSENT);
}

/** The shared body of the two plans above. Not exported: the entry points are. */
function writePlanWith(paths, schema, today, paramsMode) {
  if (!paths || typeof paths !== "object" || paths.problem || !paths.paramsPath) {
    return problem("no-params-path",
                   "There is nowhere to write a params file for this report, so nothing was written.");
  }
  // THE SERVER'S FRESH ANSWER, ALWAYS (the S1 review's D-1 obligation): a
  // `$defs` entry that also describes a nested position is copied to the
  // document root, and a copy tracks its original only within the call that
  // made it. Feeding a written file back leaves the copy silently stale.
  const file = schemaFileFor(schema);
  if (!isPlainObject(file)) {
    return problem("not-a-schema",
                   "The parameter schema the server answered is not a JSON object, so nothing was written.");
  }
  const skeleton = skeletonFrom(schema, today, paths.schemaRef);
  if (skeleton.problem) return { problem: skeleton.problem };
  return {
    embeddable: skeleton.embeddable === true,
    skeleton: skeleton.value,
    // S4: what the value MEANS, for the sentence a non-object root gets.
    shape: paramsRootShape(schema),
    files: [
      { what: WRITE_GITIGNORE, path: paths.gitignorePath, text: paramsGitignoreText, mode: WRITE_IF_ABSENT },
      { what: WRITE_SCHEMA, path: paths.schemaPath, text: schemaFileText(file), mode: WRITE_IF_DIFFERENT },
      { what: WRITE_PARAMS, path: paths.paramsPath, text: schemaFileText(skeleton.value), mode: paramsMode },
    ],
  };
}

/** What the channel says once, after the three files are written. */
function paramsWrittenNotice(paths, embeddable, shape) {
  const head = "wrote " + printable(paths && paths.paramsPath) +
               " from the report's parameter type, with " + printable(paths && paths.schemaPath) +
               " beside it (generated, and gitignored by " + printable(paths && paths.gitignorePath) + ").";
  if (embeddable !== false) {
    return head + " It is ordinary committed source: edit it, save it, and the preview re-renders.";
  }
  // **S4: SAY WHAT THE VALUE IS, not only that it is not an object.** S3's
  // sentence told the developer what the file is NOT ("not a JSON object")
  // and left them to open it and guess. Every non-object root this exporter
  // can produce is MEASURED (section 6's S4 table), so the notice can name
  // the shape: `report : Int -> Node` holds a bare number, an all-nullary
  // enum holds one of its tag strings, a `Maybe` holds `null`, `Json` holds
  // anything, and `()` holds `[]`.
  return head + " " + rootShapeSentence(shape) +
         " The file therefore carries no \"$schema\" line and the editor will not validate it; the " +
         "server still checks it and answers a 400 with a path.";
}

/** What the channel says once when the schema could not be had at all. The
  * render is NOT blocked: it goes with the inline `{}` like WP-7's. */
function schemaProblemNotice(problem0, paramsPath) {
  const p = problem0 && problem0.problem ? problem0.problem : problem0;
  return "no params file was written at " + printable(paramsPath) + ": " +
         (p && p.message ? String(p.message) : "the parameter schema could not be worked out.") +
         " The report renders with empty parameters.";
}

/** The key the glue remembers a written-or-not-written decision under, so
  * "one notice per report per session" is once. Same shape as
  * `paramsNoticeKey`, which is what keeps the two from colliding. */
function schemaNoticeKey(pick, reason) {
  return String(markKey(pick)) + MARK_SEPARATOR + "schema" + MARK_SEPARATOR + String(reason);
}

// ==========================================================================
// WP-8 S4 -- THE EDGES: U3's EXPLICIT COMMAND, D6's ORPHAN NOTICE, AND WHAT
// A NON-OBJECT PARAMS ROOT ACTUALLY MEANS.
//
// Everything here is pure and every sentence below that describes a schema
// shape was MEASURED against a real `bin/ermine-lsp`, one boot, no editor
// (section 6's S4 block; `scratchpad/wp8-s4/measure.py`, `measure.log`):
//
//   report : Int -> Node        `{"type":"integer"}`                skeleton `0`
//   an all-nullary `data`       `$ref` -> `{"enum":["Spring",...]}` skeleton `"Spring"`
//   report : Maybe String       `{"anyOf":[{string},{null}]}`       skeleton `null`
//   report : Json -> Node       `{}` (only `$schema`/`$id`)         skeleton `null`
//   report : () -> Node         `{"type":"array","maxItems":0}`     skeleton `[]`
//
// and all five RENDER (`ok=true`), which is the "the skeleton decodes" half
// of S4's own done-when.
// ==========================================================================

/** The `enum` members a sentence will name before it gives up and counts. */
const SHAPE_ENUM_SHOWN = 6;

/**
 * WHAT THE PARAMS ROOT IS, in one word and one sentence.
 *
 * Used ONLY for the non-object roots (G5): an object root needs no
 * explanation, because the `$schema` line and the editor's own completion
 * explain it.  A bare number in a file called `report.params.json` explains
 * nothing at all, which is what S3's notice left the developer with -- it
 * said what the file is NOT.
 *
 * It does ONE `$ref` hop into `$defs`, exactly as `skeletonFrom` does and
 * for the same reason (the exported root of a `data` params type is
 * `{$ref: "#/$defs/<Module>.<Type>"}` and carries nothing else, D2).  It
 * never follows a chain, because the exporter emits none
 * (`json/Schema.scala:526-532`), and a `$ref` it cannot follow answers
 * `unknown` rather than guessing.
 *
 * `kind` is a closed vocabulary so a caller can switch on it; `sentence` is
 * what the developer reads.  An `object` answers a null sentence: it has
 * nothing to say that the file does not already say.
 */
function paramsRootShape(schema) {
  const unknown = { kind: "unknown", sentence: null };
  if (schema === true) return anyRootShape();
  if (!isPlainObject(schema)) return unknown;
  const defs = isPlainObject(schema.$defs) ? schema.$defs : {};
  let node = schema;
  if (typeof node.$ref === "string") {
    const name = defNameOf(node.$ref);
    if (name === null || !Object.prototype.hasOwnProperty.call(defs, name)) return unknown;
    node = defs[name];
    if (node === true) return anyRootShape();
    if (!isPlainObject(node)) return unknown;
  }
  if (Object.prototype.hasOwnProperty.call(node, "const")) {
    return { kind: "const", sentence: "Its parameters are always " + stringify(node.const) + "." };
  }
  if (Array.isArray(node.enum)) {
    const shown = node.enum.slice(0, SHAPE_ENUM_SHOWN).map((v) => stringify(v)).join(", ");
    const rest = node.enum.length - SHAPE_ENUM_SHOWN;
    return {
      kind: "enum",
      sentence: "Its parameters are one of " + shown + (rest > 0 ? " (and " + rest + " more)" : "") +
                ", so the file holds just that value.",
    };
  }
  // A `Maybe`/`Nullable` root: the exporter writes `anyOf` with a null arm
  // (`json/Schema.scala:371`), and S1's corrected rule skeletonises it to
  // `null` -- which is what `docs/JSON-GUIDE.md:1295-1297` says such a
  // report wants. MEASURED on `WpMaybe`.
  if (Array.isArray(node.anyOf) && node.anyOf.some(admitsNull)) {
    const payload = node.anyOf.filter((a) => !admitsNull(a))[0];
    const inner = payload === undefined ? null : paramsRootShape(withDefs(payload, defs));
    return {
      kind: "optional",
      sentence: "Its parameters are optional" +
                (inner && inner.noun ? " (" + inner.noun + ")" : "") +
                ", so the file holds just that value, and `null` means there is none.",
    };
  }
  if (Array.isArray(node.oneOf)) {
    return { kind: "union", sentence: "Its parameters are one of " + node.oneOf.length +
                                      " shapes, so the file holds just that value." };
  }
  const type = Array.isArray(node.type) ? node.type[0] : node.type;
  switch (type) {
    case "object": return { kind: "object", sentence: null };
    case "array":
      // `()` is the empty tuple, and the exporter says so exactly:
      // `{"type":"array","maxItems":0}` (MEASURED on `WpUnit`).
      if (node.maxItems === 0) {
        return { kind: "unit", noun: "the empty tuple `()`",
                 sentence: "Its parameters are the empty tuple `()`, so the file holds just the empty " +
                           "array `[]` and there is nothing in it to edit." };
      }
      return { kind: "array", noun: "a JSON array",
               sentence: "Its parameters are a JSON array, so the file holds just that array." };
    case "integer": return { kind: "integer", noun: "a single whole number",
                             sentence: "Its parameters are a single whole number, so the file holds just " +
                                       "that number." };
    case "number": return { kind: "number", noun: "a single number",
                            sentence: "Its parameters are a single number, so the file holds just that " +
                                      "number." };
    case "boolean": return { kind: "boolean", noun: "a single true or false",
                             sentence: "Its parameters are a single true or false, so the file holds just " +
                                       "that word." };
    case "null": return { kind: "null", noun: "nothing at all",
                          sentence: "Its parameters are nothing at all, so the file holds just `null`." };
    case "string": return stringRootShape(node);
    default:
      // No `type` and no keyword: the exporter's `Json` position, which is
      // `Json.jEmptyObject` (`json/Schema.scala:300`) and accepts anything.
      // MEASURED on `WpJson`: the whole answer is `$schema` and `$id`.
      return anyRootShape();
  }
}

/** The `Json` root's shape. ONE builder, so the boolean schema `true` (which
  * also accepts anything) gets the same measured sentence as `{}` rather than
  * the generic fallback (the S4 review's nit 6; unreachable from today's
  * exporter, which never writes a bare `true`). */
function anyRootShape() {
  return { kind: "any", noun: "any JSON value at all",
           sentence: "Its parameters are any JSON value at all (the report takes a `Json`), so the " +
                     "file holds just that value; `null` is the smallest one that decodes." };
}

/** A `$defs`-carrying view of a nested node, so `paramsRootShape` can recurse
  * into a `Maybe`'s payload without losing the table its `$ref`s name. */
function withDefs(node, defs) {
  if (!isPlainObject(node)) return node;
  const out = cloneJson(node);
  if (!Object.prototype.hasOwnProperty.call(out, "$defs")) out.$defs = defs;
  return out;
}

/** The `string` builtins, each with the schema `json/Schema.scala:327-339`
  * writes for it, so the sentence names the Ermine type rather than "string". */
function stringRootShape(node) {
  if (node.format === "date") {
    return { kind: "date", noun: "a single date",
             sentence: "Its parameters are a single date, so the file holds just that date as a " +
                       "\"YYYY-MM-DD\" string." };
  }
  if (node.format === "date-time") {
    return { kind: "timestamp", noun: "a single timestamp",
             sentence: "Its parameters are a single timestamp, so the file holds just that timestamp as " +
                       "an ISO-8601 string with an offset." };
  }
  if (node.format === "uuid") {
    return { kind: "guid", noun: "a single GUID",
             sentence: "Its parameters are a single GUID, so the file holds just that GUID as a string." };
  }
  if (node.pattern === LONG_PATTERN) {
    return { kind: "long", noun: "a single whole number written as a string",
             sentence: "Its parameters are a single `Long`, so the file holds just that number WRITTEN AS " +
                       "A STRING -- a JSON number cannot carry 64 bits exactly." };
  }
  if (node.minLength === 1 && node.maxLength === 1) {
    return { kind: "char", noun: "a single character",
             sentence: "Its parameters are a single character, so the file holds just that one-character " +
                       "string." };
  }
  return { kind: "string", noun: "a single string",
           sentence: "Its parameters are a single string, so the file holds just that string." };
}

/** The sentence for a shape, with a fallback that is honest rather than
  * silent: a shape nothing above recognised still gets told that the file is
  * not an object. */
function rootShapeSentence(shape) {
  if (shape && typeof shape === "object" && typeof shape.sentence === "string") return shape.sentence;
  return "Its parameters are not a JSON object, so the file holds just that value.";
}

// -- U3 / G16: `Ermine: Write Params Skeleton` ------------------------------

/** The command's id, in one place, because `package.json`, `activate` and the
  * orphan notice's button all have to agree about it. */
const SKELETON_COMMAND = "ermine.writeParamsSkeleton";

/** The ONE string that consents. A dismissal (`undefined`), an Escape and
  * every other answer are a decline -- `holdRender`'s rule, for the same
  * reason: this one destroys committed source. */
const SKELETON_REPLACE = "Replace";

/**
 * MAY THE COMMAND RUN AT ALL?  (Everything it needs, before anything is
 * shown to the user or asked of the server.)
 *
 * It is NOT asked whether the report is HELD, and that is a decision with an
 * argument.  An explicit command is the user in front of the machine asking
 * for this exact thing, which is the same consent WP-22 accepts from
 * "Render anyway" and from the render command -- so the command may run
 * while held, and the glue CLEARS the mark exactly as `renderCommand` does
 * before it asks the server anything.  The consultation is still asked (with
 * `explicit`, which it never refuses), so the site exists, is pinned, and
 * cannot quietly become an automatic one: a trigger that is not `explicit`
 * would be judged on its merits.
 */
function skeletonCommandVerdict(pick, paths, hasClient) {
  if (!pick || typeof pick !== "object" || markKey(pick) === null) {
    return { run: false, reason: "no-pick",
             message: "No report is picked, so there is no params file to write. Run " +
                      "\"Ermine: Preview Report...\" first." };
  }
  if (hasClient !== true) {
    return { run: false, reason: "no-client",
             message: "The Ermine language server is not running, so the parameter schema cannot be " +
                      "worked out and no params file was written." };
  }
  if (!paths || typeof paths !== "object") {
    return { run: false, reason: "no-params-path",
             message: "There is nowhere to write a params file for " + pickLabel(pick) + "." };
  }
  if (paths.problem) {
    // The SAME named reason and the SAME sentence `paramsPaths` already
    // answers (`no-module`, `unsafe-binding`, `outside-workspace`, ...), so
    // the command and the automatic path cannot disagree about why a report
    // has no params file. S4 item 4 is this line for the two cases it names.
    return { run: false, reason: paths.problem.reason, message: paths.problem.message };
  }
  if (!paths.paramsPath) {
    return { run: false, reason: "no-params-path",
             message: "There is nowhere to write a params file for " + pickLabel(pick) + "." };
  }
  return { run: true, reason: null, message: null };
}

/**
 * THE MODAL, WORD FOR WORD.  It NAMES THE FILE and says what happens to what
 * is in it -- U3's own two requirements -- and it says what will not be
 * touched, because "replace" beside three file names would read as all three.
 */
function skeletonConfirmation(paths) {
  return {
    message: "Replace " + printable(paths && paths.paramsPath) + " with a fresh skeleton?\n\n" +
             "Everything in that file now -- every value you have edited, and anything you have not " +
             "committed -- is REPLACED by the defaults derived from the report's parameter type. This " +
             "cannot be undone from here; git can. The generated schema file beside it is refreshed too.",
    confirm: SKELETON_REPLACE,
  };
}

/** Only the exact consenting string is consent. */
function skeletonConfirmed(choice) {
  return choice === SKELETON_REPLACE;
}

/**
 * DOES THE ANSWER TO THE MODAL STILL DESCRIBE THE REPORT IT WAS ASKED ABOUT?
 *
 * A modal is an `await` the user can hold open for minutes, and in that time
 * the pick can change, a header edit can move the MODULE (which is the
 * DIRECTORY the file would be written into) and `ermine.preview.roots` can
 * resolve somewhere else.  `isCurrentSchemaAnswer` is exactly those four
 * fields and it is already the D7 guard, so it is REUSED rather than a
 * second identity test being minted -- but the answer is dressed with a
 * sentence, because unlike D7 this one is shown to the person who answered.
 *
 * **`mayStillSend` IS DELIBERATELY NOT USED HERE**, and the reason is its
 * `superseded` arm: it refuses when the generation has moved, which is right
 * for a render (a newer one is already going) and WRONG for this command (a
 * background save-triggered render must not cancel what the user explicitly
 * asked for). The restart/stop arms it also carries are not needed either:
 * the snapshot this command sends its schema request on is taken AFTER the
 * modal, so a restart during the modal is simply a request to the fresh
 * server, which is what the user wants.
 */
function skeletonStillApplies(askedPick, pickNow) {
  if (isCurrentSchemaAnswer(askedPick, pickNow)) return { apply: true, why: null };
  return {
    apply: false,
    why: "the picked report moved from " + pickLabel(askedPick) + " to " + pickLabel(pickNow) +
         " while the question was on screen, so nothing was written",
  };
}

/** What the channel and the notification say when the command replaced a file. */
function skeletonReplacedNotice(paths, embeddable, shape) {
  const head = "replaced " + printable(paths && paths.paramsPath) +
               " with a fresh skeleton from the report's parameter type, and refreshed " +
               printable(paths && paths.schemaPath) + " beside it.";
  return embeddable === false
    ? head + " " + rootShapeSentence(shape)
    : head + " Edit it, save it, and the preview re-renders.";
}

/**
 * THE ONE SENTENCE A WRITTEN SKELETON GETS, for BOTH writers (the automatic
 * first pick and U3's command). **A SHARED BUILDER, BECAUSE THE MODEL
 * DRIFTED** (the S4 review's M-4): the glue passed `plan.shape` and the
 * first-pick model did not, so every model test of the automatic notice read
 * the generic fallback sentence and dropping `plan.shape` from the glue was
 * caught by a source pin only. Glue and models now hand over the PLAN, and
 * which of its fields reach the sentence is decided here, once.
 */
function skeletonWrittenNotice(paths, plan, replace) {
  const embeddable = plan && typeof plan === "object" ? plan.embeddable : undefined;
  const shape = plan && typeof plan === "object" ? plan.shape : undefined;
  return replace === true
    ? skeletonReplacedNotice(paths, embeddable, shape)
    : paramsWrittenNotice(paths, embeddable, shape);
}

/**
 * U2's "ONCE PER PATH PER SESSION", and S4's `always` (U3's command), as ONE
 * decision the glue's `openParamsDocument` and both models call (the S4
 * review's M-4: neither model reproduced the dedupe, so dropping `always`
 * was caught by a definition pin only). It ADDS the path when it answers
 * true -- the glue's set is mutated here, the same way, at the same moment,
 * in the glue and in the model (the header rule of the test file).
 */
function claimParamsDocument(opened, fsPath, always) {
  if (opened.has(fsPath) && always !== true) return false;
  opened.add(fsPath);
  return true;
}

/**
 * THE MODAL-TO-WRITE TOCTOU, DECIDED: RE-READ AND REFUSE (2026-09-23).
 *
 * `existing` is read BEFORE the modal, and between the user's Replace and
 * the write there is a whole `ermine/schema` round trip (a compile and an
 * evaluation: seconds). MEASURED by the S4 review (probe/overwrite.js case
 * 4): a file edited and saved in that window was DESTROYED, and the bytes
 * destroyed were not the bytes the modal named -- `files.autoSave:
 * onFocusChange` can flush a dirty buffer into that window by machinery,
 * with nobody racing on purpose. S4 already applied this discipline to the
 * PICK (`skeletonStillApplies`); this is the same rule for the BYTES.
 *
 * The glue re-reads the params file AFTER the schema answer and BEFORE the
 * write and passes both reads. A replace proceeds only when they are the
 * SAME STRING; a file that changed OR VANISHED is refused by name, nothing
 * is written, nothing is rendered and the wedge mark is not spent. A CREATE
 * (`replace !== true`) is not judged here: it goes through the race-safe
 * create, which never overwrites and already answers `existed`.
 *
 * It narrows the window to the re-read-to-write gap; it does not close it
 * (`workspace.fs` has no compare-and-swap), and it does not claim to. It
 * compares DECODED UTF-8 text, so two different invalid byte sequences can
 * compare equal (re-review nit 2); a params file is JSON, so this is stated
 * rather than fixed. A re-read that FAILS answers null and is refused too.
 */
function skeletonBytesStillApply(replace, before, now, paramsPath) {
  if (replace !== true) return { apply: true, reason: null, message: null };
  if (typeof before === "string" && typeof now === "string" && before === now) {
    return { apply: true, reason: null, message: null };
  }
  return {
    apply: false,
    reason: "params-changed",
    message: 'the params file "' + printable(paramsPath) + '" ' + (now === null ? "was removed or could not be read" : "changed") +
             " after you were asked (while the question was on screen or while the schema was being " +
             "worked out), so nothing was written; run the command again",
  };
}

/** `writeParamsSkeleton`'s answer, minted once so the model cannot drift from
  * the glue (the S3 review's M-1, applied to S4's own new shape). */
function skeletonCommandResult(over) {
  const o = over && typeof over === "object" ? over : {};
  return {
    wrote: o.wrote === true,
    replaced: o.replaced === true,
    existed: o.existed === true,
    abandoned: o.abandoned === true,
    problem: o.problem || null,
  };
}

// -- D6: the ORPHAN notice -------------------------------------------------

/** `vscode.FileType.File`. Written here for the reason `FILE_TYPE_SYMLINK` is
  * (`@types/vscode` `index.d.ts`): this file never requires `vscode`, and the
  * load test's stub answers 0 for a member it does not define. */
const FILE_TYPE_FILE = 1;

/** The suffix that makes a directory entry one of ours. */
const PARAMS_SUFFIX = ".params.json";

/** The notification's button. It runs the command for the CURRENT pick --
  * the stale binding is gone, so there is nothing to write for IT. */
const ORPHAN_BUTTON = "Write Params Skeleton";

/**
 * **THE SHAPE A DIRECTORY LISTING REACHES A DECISION IN, MINTED ONCE** (the
 * S3 review's M-1 and the delta re-review's D-1, applied before the defect
 * rather than after it).  `vscode.workspace.fs.readDirectory` answers
 * `[name, FileType][]`; the glue converts, the model calls THIS, and the
 * three arms are always all present so `if (listing.problem)` cannot read
 * `undefined` off a shape that forgot to declare itself.
 *
 *   `entries`  the directory was read;
 *   `missing`  there is no such directory (the ordinary case before the
 *              first write, and NOT a problem);
 *   `problem`  it is there and we could not read it -- which is NOT "there
 *              is nothing stale", the same distinction `statType`'s third
 *              answer exists for (D-2).
 */
function directoryListing(over) {
  const o = over && typeof over === "object" ? over : {};
  const out = { entries: null, missing: false, problem: null };
  if (o.problem !== undefined && o.problem !== null) {
    out.problem = o.problem && o.problem.problem ? o.problem.problem : o.problem;
    return out;
  }
  if (o.missing === true) {
    out.missing = true;
    out.entries = [];
    return out;
  }
  if (Array.isArray(o.entries)) {
    out.entries = o.entries.map((e) => {
      if (Array.isArray(e)) return { name: String(e[0]), type: typeof e[1] === "number" ? e[1] : null };
      if (e && typeof e === "object") {
        return { name: String(e.name), type: typeof e.type === "number" ? e.type : null };
      }
      return { name: String(e), type: null };
    });
    return out;
  }
  // FAIL CLOSED, like every other unknown in this file.
  out.problem = problem("bad-listing",
                        "The preview was handed a directory listing it cannot read (" +
                        printable(typeName(o.entries)) + "), so nothing was called stale.").problem;
  return out;
}

/**
 * **D6: WHICH PARAMS FILES UNDER THIS MODULE'S DIRECTORY NAME A BINDING THE
 * SERVER NO LONGER OFFERS?**
 *
 * Renaming or deleting a report's binding leaves its params file behind
 * under the old name.  Nothing breaks -- the new binding gets its own file
 * on the next pick -- but the old one stays in the repository, committed,
 * looking current, and the developer finds it months later.  §6's Rename row
 * says "nothing fails silently"; this is the half that says it.
 *
 * **IT IS A COMPARISON AND NOTHING ELSE.  NOTHING IS EVER DELETED**, here or
 * in the glue: the file is committed source, `git status` already shows it,
 * and an extension that deletes a developer's committed file because a
 * server answer did not mention it is one bad answer away from losing work.
 * The notice names it and offers U3's command; the `rm` is the developer's.
 *
 * **IT FAILS CLOSED IN THREE PLACES, and each is a way of calling a file
 * stale when it is not:**
 *   the listing could not be read     -> a problem, no orphans;
 *   `reports` is not an ARRAY         -> the server could not list the file
 *                                        (a parse error, a 404), so nothing
 *                                        can be called stale;
 *   `reports` is EMPTY                -> the module compiles to no
 *                                        report-typed binding at all, which
 *                                        is almost always a module that is
 *                                        broken right now.  Calling EVERY
 *                                        params file stale at that moment is
 *                                        exactly wrong.
 * A name that is not one we could have minted (`SAFE_NAME`) is skipped too,
 * and so is any entry that is not a plain FILE -- a directory called
 * `x.params.json`, or a symbolic link, which this extension never touches.
 *
 * **WHAT IT DOES NOT COVER, SAID OUT LOUD: A RENAMED MODULE.**  When the
 * module's own name moves, the whole `.ermine/preview/<OldModule>/`
 * directory is stale and nothing here looks inside it -- this function is
 * only ever asked about the CURRENT pick's module directory.  Detecting it
 * means knowing every module declared under the roots, and the extension has
 * no such map: `ermine/preview/reports` answers for ONE file, so the cheapest
 * honest implementation is one request per `.e` file in the workspace, on
 * the preview queue, each of which COMPILES a module.  That is not cheap, it
 * is not what a pick should cost, and so it is NOT BUILT.  The stale
 * directory is visible in `git status` like any other committed file, and
 * section 6's S4 block records this as a known gap rather than a surprise.
 *
 * @param {object} listing `directoryListing`'s answer
 * @param {Array} reports `ermine/preview/reports`'s `reports` array
 * @param {object} paths `paramsPaths`'s answer, for the orphans' full paths
 * @param {"posix"|"win32"=} flavour the path flavour, default the host's
 */
function orphanParamsFiles(listing, reports, paths, flavour) {
  const none = (why) => ({ orphans: [], problem: null, why: why });
  if (!listing || typeof listing !== "object") {
    return { orphans: [], problem: problem("bad-listing", "There is no directory listing to compare.").problem,
             why: null };
  }
  if (listing.problem) return { orphans: [], problem: listing.problem, why: null };
  if (listing.missing === true) {
    return none("there is no params directory for this module yet, so nothing can be stale");
  }
  if (!Array.isArray(listing.entries)) {
    return { orphans: [], problem: problem("bad-listing", "The directory listing is not a list.").problem,
             why: null };
  }
  if (!Array.isArray(reports)) {
    return none("the language server did not list this file's reports, so nothing can be called stale");
  }
  if (!reports.length) {
    return none("the language server offered no report-typed binding at all -- which usually means the " +
                "module does not compile right now -- so nothing is called stale");
  }
  const p = pathFlavour(flavour);
  // WIN32 ONLY: THE FILE SYSTEM FOLDS CASE, SO THE COMPARE DOES (the S4
  // review's nit 2). `Report.params.json` on NTFS IS the file the extension
  // reads for binding `report`, so calling it an orphan of `report` would be
  // advice to delete a live file. On POSIX the names are distinct files and
  // the compare stays exact.
  const fold = p === path.win32 ? (x) => x.toLowerCase() : (x) => x;
  const offered = {};
  for (const r of reports) {
    if (r && r.binding !== undefined && r.binding !== null) defineKey(offered, fold(String(r.binding)), true);
  }
  const orphans = [];
  for (const entry of listing.entries) {
    if (!entry || typeof entry.name !== "string") continue;
    if (entry.name.length <= PARAMS_SUFFIX.length) continue;
    if (fold(entry.name.slice(-PARAMS_SUFFIX.length)) !== PARAMS_SUFFIX) continue;
    // A plain FILE and nothing else: a symbolic link (the `SymbolicLink` bit)
    // and a directory are both left alone, because we never touch either and
    // naming one "stale" would be advice to delete something we did not write.
    if (entry.type !== FILE_TYPE_FILE) continue;
    const binding = entry.name.slice(0, entry.name.length - PARAMS_SUFFIX.length);
    if (binding.length > MAX_NAME_LENGTH || !SAFE_NAME.test(binding)) continue;
    if (Object.prototype.hasOwnProperty.call(offered, fold(binding))) continue;
    orphans.push({
      binding: binding,
      fileName: entry.name,
      path: paths && paths.dir ? p.join(paths.dir, entry.name) : entry.name,
    });
  }
  return { orphans: orphans, problem: null,
           why: orphans.length ? null : "every params file here names a binding the server still offers" };
}

/** ONE NOTICE PER (MODULE, BINDING) PER SESSION -- keyed by the MODULE and
  * not by the pick, because the orphan belongs to the directory and the same
  * stale file is found again from every binding in that module. */
function orphanNoticeKey(pick, binding) {
  return String(pick && pick.module) + MARK_SEPARATOR + "orphan" + MARK_SEPARATOR + String(binding);
}

/**
 * WHAT THE ORPHAN NOTICE SAYS.  It names the file, says why it is being
 * mentioned, says the file is the developer's to delete, and says what the
 * button does -- which is NOT "fix this file": the stale binding is gone, so
 * the button writes a fresh skeleton for the report that is picked NOW.
 */
function orphanNoticeText(orphan, pick) {
  // "OR HAS MADE IT PRIVATE" (the S4 review's nit 1): a binding made private
  // leaves the offered list exactly as a deleted one does
  // (`Definitions.scala:308` filters private names), so the sentence does
  // not claim to know which of the two happened.
  return printable(orphan && orphan.path) + " is left over: " + printable(pick && pick.module) +
         ' no longer offers a report called "' + printable(orphan && orphan.binding) + '"' +
         " (it was renamed or removed, or the module has made it private), so nothing reads that file. It is committed source, so the preview will not delete it -- " +
         "delete it yourself once you are sure. \"" + ORPHAN_BUTTON + "\" writes a fresh skeleton for " +
         pickLabel(pick) + ", the report picked now.";
}

/**
 * WHAT THE SCAN SAYS, AND WHAT IT HAS ALREADY SAID -- one decision for the
 * glue's `noticeOrphanParamsFiles` and the model (the S4 review's nit 3:
 * R24, "the unreadable-directory line is never said", SURVIVED because the
 * glue decided it inline and the model's copy was never asserted). It
 * ADDS to `seen` (the glue's `orphanNotices`) exactly the keys it answers
 * for, so "once per (module, binding) per session" is decided here too.
 *
 * Answers `{listingLine, orphans: [{orphan, text}]}`: a line for the channel
 * when the directory could not be listed (once per module), else one entry
 * per orphan not yet noticed, whose text is both logged and notified.
 */
function orphanNoticePlan(found, pick, seen, dir) {
  const out = { listingLine: null, orphans: [] };
  if (!found || typeof found !== "object") return out;
  if (found.problem) {
    const key = orphanNoticeKey(pick, "listing");
    if (!seen.has(key)) {
      seen.add(key);
      out.listingLine = orphanListingNotice(found.problem, dir);
    }
    return out;
  }
  for (const orphan of found.orphans || []) {
    const key = orphanNoticeKey(pick, orphan.binding);
    if (seen.has(key)) continue;
    seen.add(key);
    out.orphans.push({ orphan, text: orphanNoticeText(orphan, pick) });
  }
  return out;
}

/** What the channel says when the params directory is there and unreadable.
  * NOT a refusal of anything: the render and the writes are unaffected. */
function orphanListingNotice(problem0, dir) {
  const p = problem0 && problem0.problem ? problem0.problem : problem0;
  return "could not list " + printable(dir) + " (" +
         (p && p.message ? String(p.message) : "the editor did not say why") +
         "), so left-over params files under it were not looked for. Nothing else is affected.";
}

// -- S3 review: the shapes the glue hands its own decisions ----------------
//
// **THE FOURTH OCCURRENCE OF THIS BRANCH'S RECURRING DEFECT, AND THE LAST
// ONE THAT CAN HAPPEN THIS WAY** (the S3 review's M-1). The test file's
// header states the rule -- *a model must mutate, omit and capture exactly
// what the glue mutates, omits and captures* -- and it had been broken three
// times before. It was broken a fourth: `prepareParams` built its answer as
// four separate object literals in `extension.js` while the model's
// read-settlers built their own, and the model's `renderNow` read a model
// constant where the glue reads `prepared.paths`. Deleting the single word
// `paths,` from ONE of those literals turned the whole stage off -- no file
// ever written, no schema ever asked for -- with **249 of 249 tests green**
// (MEASURED by the review, reproduced here).
//
// A pin would have caught that ONE field. The builders below stop the CLASS:
// every object the glue hands to an S3 decision is minted by ONE exported
// pure function that BOTH the glue and the model call, so a field cannot be
// present on one side and absent on the other. What is left to a pin is only
// that the glue calls them, which is a much smaller thing to get wrong and
// a much easier one to see.

/** The four outcomes `prepareParams` can have, closed. */
const PREPARED_PATH_PROBLEM = "path-problem";
const PREPARED_MISSING = "missing";
const PREPARED_READ = "read";
const PREPARED_REFUSAL = "refusal";
const PREPARED_KINDS = [PREPARED_PATH_PROBLEM, PREPARED_MISSING, PREPARED_READ, PREPARED_REFUSAL];

/**
 * THE SHAPE `prepareParams` ANSWERS, MINTED IN ONE PLACE (M-1).
 *
 * Every field the send path reads is set here for every outcome:
 *   `params`    what goes on the wire (absent for a refusal, which sends
 *               nothing);
 *   `paths`     `paramsPaths`'s answer, **always**, including its `{problem}`
 *               form -- `schemaOrder` is what reads it, and a dropped
 *               `paths` silently answers "there is nowhere to write";
 *   `path`      the params file, for the notices and the refusal answer;
 *   `notice`    one named sentence, or absent;
 *   `refusal`   a named `paramsToSend`/read problem, or absent;
 *   `read`      true only when a file was really read;
 *   `warnings`  U5's credential warnings.
 *
 * @param {object} paths `paramsPaths`'s answer (or its `{problem}` form)
 * @param {{kind, params, problem, warnings}} outcome what the disk said
 */
function preparedParams(paths, outcome) {
  const o = outcome && typeof outcome === "object" ? outcome : {};
  const has = paths && typeof paths === "object" && !paths.problem && paths.paramsPath;
  const prepared = {
    paths: paths === undefined ? null : paths,
    path: has ? paths.paramsPath : null,
  };
  switch (o.kind) {
    case PREPARED_PATH_PROBLEM:
      prepared.params = {};
      prepared.notice = paths && paths.problem
        ? { reason: paths.problem.reason, line: paths.problem.message }
        : { reason: "no-params-path", line: "this report has no params path." };
      return prepared;
    case PREPARED_MISSING:
      prepared.params = {};
      prepared.notice = { reason: PREPARED_MISSING, line: paramsMissingNotice(prepared.path) };
      return prepared;
    case PREPARED_READ:
      prepared.params = o.params;
      prepared.warnings = o.warnings || [];
      prepared.read = true;
      return prepared;
    case PREPARED_REFUSAL:
      prepared.refusal = o.problem && o.problem.problem ? o.problem.problem : o.problem;
      return prepared;
    default:
      // FAIL CLOSED, like every other unknown in this file: a kind nothing
      // declared refuses rather than rendering something unspecified.
      prepared.refusal = problem("bad-prepared-kind",
                                 "The parameters were prepared with an outcome nothing declares (" +
                                 printable(typeName(o.kind)) + "), so the report was not rendered.").problem;
      return prepared;
  }
}

// -- M-2: the write plan's modes, shared by producer and consumer ----------

/** Create it if it is not there; NEVER touch one that is. */
const WRITE_IF_ABSENT = "ifAbsent";
/** Rewrite it only when its bytes differ (D8). */
const WRITE_IF_DIFFERENT = "ifDifferent";
/**
 * **S4 / U3: REPLACE IT, WHATEVER IS THERE -- THE ONE MODE THAT MAY TOUCH
 * COMMITTED SOURCE, AND IT IS NOT REACHABLE FROM ANY ANSWER.**
 *
 * U3 is the user's decision: *"an explicit `Ermine: Write Params Skeleton`
 * command that overwrites after confirmation; never a silent merge into
 * committed source."*  Everything about this mode exists to keep the second
 * half of that sentence true:
 *
 *   the MODE is not authority.  `writeStep` refuses it unless its caller
 *   ALSO passes `allowExplicitOverwrite === true`, so a plan carrying this
 *   mode that reaches any other write loop writes NOTHING.  M-2's lesson was
 *   that a fail-OPEN default at this site destroys committed source, and a
 *   mode that authorised itself would be the same defect wearing a name;
 *
 *   it applies to the PARAMS FILE and to nothing else.  A `.gitignore` or a
 *   `<binding>.schema.json` carrying it is refused: those two already have
 *   their own modes, and a mode that works everywhere is a mode that will
 *   one day be pasted somewhere;
 *
 *   there is exactly ONE plan that mints it (`skeletonCommandPlan`, with a
 *   strict `replace === true`), exactly one caller of that plan, and exactly
 *   one caller of the write loop that passes the permission -- the command
 *   handler `activate` registers.  Source pins hold all three, because the
 *   chain is the safety argument and no behavioural test can see it.
 */
const WRITE_EXPLICIT_OVERWRITE = "explicitOverwrite";
/** The plan's `what` values, so producer and consumer cannot drift. */
const WRITE_GITIGNORE = "gitignore";
const WRITE_SCHEMA = "schema";
const WRITE_PARAMS = "params";

/**
 * WHAT TO DO WITH ONE ENTRY OF THE PLAN, AND IT FAILS **CLOSED** (M-3 of the
 * S3 review... M-2).
 *
 * The first cut wrote `if (mode === "ifAbsent") create; else OVERWRITE`. Any
 * mode that was not that exact string fell through to an unconditional
 * `workspace.fs.writeFile` of whatever path the entry named -- at the one
 * site in this extension that can destroy the developer's committed source.
 * **MEASURED by the review on a real disk: an entry `mode: "ifabsent"`, one
 * lowercase letter, overwrote `{"COMMITTED":"SOURCE"}` with the skeleton and
 * reported `{"wrote":["params"]}`.** It was not live -- `paramsWritePlan`
 * spells it correctly and a table test pins that -- but it was a fail-OPEN
 * default in a file that fails CLOSED everywhere else it matters
 * (`triggerProblem`, `shouldRefreshSchema`, `schemaOrder`'s strict `true`,
 * `schemaFileNeedsWrite`'s unreadable-compares-unequal).
 *
 * TWO RULES, AND THE SECOND IS BELT AND BRACES:
 *   an unknown mode is a NAMED REFUSAL, never a write;
 *   **the params file is refused by any route but the create**, whatever the
 *   mode says -- identified BOTH by `what` and by its path, so neither a
 *   mislabelled entry nor a retyped mode can reach an overwrite.
 *
 * **S4 ADDS EXACTLY ONE DOOR AND LOCKS IT FROM THE OUTSIDE.**  U3's command
 * must replace a params file, so `WRITE_EXPLICIT_OVERWRITE` exists -- but
 * the MODE does not authorise itself: the caller must pass
 * `allowExplicitOverwrite === true` as well, and only the command's own
 * write loop does.  Every pre-S4 caller passes two arguments, so for them
 * the third is `undefined` and the mode is refused, which is what makes the
 * rule above ("refused by any route but the create") still true of the
 * first-pick path word for word.  The overwrite is also refused for
 * anything that is not the params file.
 */
function writeStep(file, paramsPath, allowExplicitOverwrite) {
  if (!file || typeof file !== "object" || typeof file.path !== "string" || !file.path) {
    return { problem: problem("bad-write-entry",
                              "The preview was handed a write it cannot describe, so nothing was written.").problem };
  }
  if (file.mode === WRITE_IF_ABSENT) return { act: WRITE_IF_ABSENT, problem: null };
  const isParams = file.what === WRITE_PARAMS ||
                   (typeof paramsPath === "string" && paramsPath !== "" && file.path === paramsPath);
  if (file.mode === WRITE_EXPLICIT_OVERWRITE) {
    if (allowExplicitOverwrite !== true) {
      return { problem: problem("overwrite-not-permitted",
                                'The preview was asked to REPLACE "' + printable(file.path) +
                                "\" from somewhere that may not replace anything. Only the " +
                                "\"Ermine: Write Params Skeleton\" command overwrites a params file, and " +
                                "only after you confirm it, so nothing was written.").problem };
    }
    // M-1 of the S4 review: the OVERWRITE needs BOTH the label AND the path.
    // `isParams` above is a DISJUNCTION, which is right for the refusal
    // below (either sign is enough to refuse) and fail-OPEN here: MEASURED,
    // {what:"params", path:<the schema file>} overwrote the schema file.
    const isTheParamsFile = file.what === WRITE_PARAMS &&
                            typeof paramsPath === "string" && paramsPath !== "" && file.path === paramsPath;
    if (!isTheParamsFile) {
      return { problem: problem("overwrite-not-params",
                                'The preview was asked to REPLACE "' + printable(file.path) +
                                "\", which is not the params file. Only the params file is ever replaced, " +
                                "so nothing was written.").problem };
    }
    return { act: WRITE_EXPLICIT_OVERWRITE, problem: null };
  }
  if (isParams) {
    return { problem: problem("params-not-creatable",
                              'The params file "' + printable(file.path) + '" would have been written by ' +
                              printable(String(file.mode)) + " rather than created. It is committed source " +
                              "and is only ever CREATED, so nothing was written.").problem };
  }
  if (file.mode === WRITE_IF_DIFFERENT) return { act: WRITE_IF_DIFFERENT, problem: null };
  return { problem: problem("unknown-write-mode",
                            'The preview does not know how to write "' + printable(file.path) + '" (' +
                            printable(String(file.mode)) + "), so nothing was written.").problem };
}

// -- M-3: symlinks, which S1 handed to S3 and S3 must answer ---------------

/**
 * VS Code's `FileType` is a BITMASK and a symlink is reported as
 * `SymbolicLink | File` or `SymbolicLink | Directory` (*external*: the
 * documented API). **THE NUMBER IS WRITTEN HERE RATHER THAN READ OFF
 * `vscode.FileType`, on purpose**: this file never requires `vscode`, and
 * the load test's stub answers `0` for any capitalised member it does not
 * define -- which would silently turn the mask into "nothing is ever a
 * symlink", the exact failure this constant exists to prevent.
 */
const FILE_TYPE_SYMLINK = 64;

/**
 * WHICH PATHS MUST BE `stat`ed BEFORE A WRITE, in order, outermost first.
 *
 * Every directory component this extension might write THROUGH, plus the
 * files it is about to touch. `<folder>/.ermine` and `<folder>/.ermine/preview`
 * are included because `createDirectory` would happily make the module
 * directory inside a symlinked `preview/`, and the writes would then land
 * wherever that link points.
 *
 * The workspace folder's own path is NOT included: it is what the developer
 * opened, it is `paramsFolderFor`'s answer, and refusing to write inside a
 * workspace somebody reached through a link would refuse the ordinary
 * `/home/me/work -> /mnt/big/work` setup for no gain.
 */
function writeTargetPaths(paths, targets, flavour) {
  const p = pathFlavour(flavour);
  if (!paths || typeof paths !== "object" || paths.problem || !paths.previewDir) return [];
  const out = [p.dirname(paths.previewDir), paths.previewDir, paths.dir];
  for (const t of targets || []) {
    if (typeof t === "string" && t && out.indexOf(t) < 0) out.push(t);
  }
  return out;
}

/**
 * IS ANY OF THEM A SYMLINK? (the S3 review's M-3.)
 *
 * The glue `stat`s each path `writeTargetPaths` answers and hands back
 * `{path, type}` for each one that EXISTS (a path that is not there, or that
 * cannot be stat'd, contributes nothing -- it is about to be created by us,
 * or the write will fail with its own message). This refuses the first
 * symlink it finds, by name.
 *
 * **WHY REFUSE RATHER THAN RESOLVE.** Resolving needs `realpath`, which
 * `workspace.fs` does not offer; and following a link would have to re-run
 * G1's containment test against the resolved path, which is S1's and is pure.
 * Refusing costs a developer who deliberately symlinked their `.ermine`
 * directory -- who is told exactly which path stopped it -- and buys the
 * thing the review MEASURED going wrong: a `<binding>.schema.json` symlinked
 * outside the workspace written THROUGH from the refresh path, which is
 * reachable from an ANSWER, and a DANGLING params symlink creating the
 * skeleton at its outside target.
 *
 * **IT IS NOT A DEFENCE AGAINST A CONCURRENT ATTACKER, AND IT DOES NOT CLAIM
 * TO BE.** A link created between this check and the write is not caught --
 * nothing short of an `O_NOFOLLOW` create could be, and `workspace.fs` has
 * no such door. What the `ifAbsent` create still guarantees in that window is
 * the thing that matters most: an existing regular file is never truncated.
 *
 * **UNVERIFIED**: whether VS Code's `workspace.fs.stat` really reports the
 * `SymbolicLink` bit as documented, and whether its `writeFile` /
 * `WorkspaceEdit.createFile` follow links at all. Node's `fs` does follow
 * them (MEASURED), and assuming the editor does not would be an assumption
 * in the dangerous direction.
 */
function writeTargetProblem(seen) {
  for (const entry of seen || []) {
    if (!entry || typeof entry !== "object") continue;
    // **D-2: "CANNOT TELL" IS NOT "NOT THERE", AND IT FAILS CLOSED.** The
    // first cut answered `null` for every `stat` that threw, so a path that
    // EXISTS but cannot be stat'd -- EACCES on the directory above it, a
    // provider that refuses -- voided the whole defence. MEASURED: a schema
    // symlink outside the workspace was written THROUGH. A path that is
    // really absent contributes nothing (we are about to create it); a path
    // we could not read the type of refuses, by name.
    // **ANY `unknown` KEY REFUSES (the final check's N-g).** This used to
    // test the string's TRUTHINESS as well, so a provider that threw an
    // EMPTY message answered `{unknown: ""}` and the defence answered null
    // -- fail-OPEN on truthiness, one level below the shape D-2 closed.
    if ("unknown" in entry) {
      const why = typeof entry.unknown === "string" && entry.unknown
        ? entry.unknown : "the editor did not say why";
      return problem("unstattable",
                     'The preview could not tell what "' + printable(entry.path) + '" is (' +
                     why + "), so it will not write there: it cannot rule out a symbolic " +
                     "link pointing outside the workspace folder. Nothing was written; the report " +
                     "renders with empty parameters.").problem;
    }
    if (typeof entry.type !== "number" || !isFinite(entry.type)) continue;
    if ((entry.type & FILE_TYPE_SYMLINK) === 0) continue;
    return problem("symlink",
                   'The preview will not write through the symbolic link "' + printable(entry.path) +
                   '": it cannot tell where it points, and a params or schema file written through one ' +
                   "would land outside the workspace folder. Nothing was written; the report renders " +
                   "with empty parameters.").problem;
  }
  return null;
}

// -- the remaining shapes the glue hands its own decisions (M-1's audit) ---

/** `createFileWithoutOverwriting`'s answer, minted once. */
const CREATED = "created";
const EXISTED = "existed";
const CREATE_FAILED = "failed";
function createOutcome(outcome, why) {
  return { outcome: outcome, why: typeof why === "string" ? why : null };
}

/**
 * WHAT A FAILED CREATE SAYS, MINTED ONCE (M-1's treatment, applied to the
 * last shape that was still built twice).
 *
 * **N-5 IS IN THIS SENTENCE**: the generated `.gitignore` is a convenience
 * and its failure does not stop the two files that matter, so it says
 * something different from the two that do -- and the model said something
 * different again until this builder existed.
 */
function writeFailedProblem(what, filePath, why) {
  return {
    reason: "write-failed",
    message: 'The preview could not create "' + printable(filePath) + '" (' + String(why) +
             (what === WRITE_GITIGNORE
               ? "). The params and schema files are written anyway; only the generated .gitignore " +
                 "is missing, so `git status` will show the schema file too."
               : "), so the report renders with empty parameters."),
  };
}

/** `applyWritePlan`'s answer, minted once. `problems` is always an array and
  * `wrote` always the list of `what`s this run really created or rewrote. */
function writeOutcome(over) {
  const o = over && typeof over === "object" ? over : {};
  return {
    wrote: Array.isArray(o.wrote) ? o.wrote : [],
    existed: o.existed === true,
    problems: Array.isArray(o.problems) ? o.problems : [],
  };
}

/** `requestSchema`'s "the world moved" answer, through the SAME builder as
  * its other two arms (D-1): the model minted a literal `{abandoned: still}`
  * where the glue called this, which is M-1's shape with the sign reversed. */
function schemaAbandoned(verdict) {
  return schemaOutcome({
    abandoned: verdict && typeof verdict === "object"
      ? verdict
      : { reason: "pick-cleared", why: "there is nothing to ask about" },
  });
}

/**
 * `firstPickSchemaAndWrite`'s answer (D-1's builder audit): nine raw
 * `{wrote: ...}` literals on the glue's side and their counterparts in the
 * model, which is exactly the shape M-1 was about. `wrote` means "a params
 * file is now on disk", which is what decides whether the caller has a
 * render to schedule.
 */
function firstPickResult(over) {
  const o = over && typeof over === "object" ? over : {};
  return { wrote: o.wrote === true, raced: o.raced === true, abandoned: o.abandoned === true };
}

/** `writeIfDifferent`'s answer, for the same reason. */
function writeResult(over) {
  const o = over && typeof over === "object" ? over : {};
  return { wrote: o.wrote === true, problem: o.problem || null };
}

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

// ------------------------------------------------ the panel (WP-10, S1)
//
// THE PURE HALF OF THE WEBVIEW PANEL.  Nothing here is wired: `extension.js`
// creates no panel, posts nothing and reads none of this until S2.  What S1
// fixes is the CONTRACT S2's glue and every test must share, per the rule at
// the head of test/preview-core.test.js (a model must capture exactly what the
// glue captures): the glue will build the panel's view with `panelView` --
// the SAME builder the tests call -- and post exactly `panelMessagesFor(view)`.
//
// THE BOUNDARY (the WP-9 review's D10, kept): every DECISION stays on this
// side.  `client/src/host/index.ts`'s `applyMessage` is a PRESENTATION
// reducer: it is handed messages that have already been believed.  So:
//
//   * is this answer current?    `isCurrentGeneration`, inside `panelAnswerStep`
//   * was this render displaced? `isDisplaced`, inside `panelAnswerStep`
//   * is the wedge stuck?        `stuckReduce`'s state, handed in whole; this
//                                code NEVER reads an answer's own `stuck` key,
//                                because that marker is per-request and rule
//                                (3) decides whether it applies
//   * is the pick held?          `heldMessage(mark, pick)`, the same
//                                `markMatches` consultation the status bar uses
//
// THE LIST IS A SNAPSHOT, NOT A DELTA (design review H7/H10).  `postMessage`
// to a webview that is not live is DOCUMENTED to drop the message
// (`@types/vscode` index.d.ts:10018-10019), so the panel can miss any single
// post; the resync on `ready` / visibility must therefore carry EVERY slice.
// `panelMessagesFor` always emits `stale`, `stuck`, `held`, `offline`,
// `switching` and `unsaved`, so the list folded onto ANY reachable panel state
// equals the list folded from a fresh one (`client/test/page.test.ts`'s
// `(pg-h7-*)` properties drive the REAL reducer over the REAL builders).

/** The nine kinds of `client/src/host/index.ts`'s `MESSAGE_KINDS`, in its order. */
const PANEL_MESSAGE_KINDS = Object.freeze([
  "render", "error", "stale", "stuck", "held", "offline", "switching", "unsaved", "reloadBundle",
]);

/**
 * U1, TAKEN BY THE ORCHESTRATOR on the design review's recommendation (b), NOT
 * asked of the user: `ermine.preview.target` is `panel | json | both`, default
 * `panel`.  S1 declares the contract only; S2 contributes the setting and
 * reads it.  An unknown value is REFUSED AND NAMED and the default is used,
 * the same shape as `previewSettings`' refusals.
 */
const PANEL_TARGETS = Object.freeze(["panel", "json", "both"]);
const PANEL_TARGET_DEFAULT = "panel";

function panelTarget(raw) {
  if (raw === undefined || raw === null || raw === "") return { target: PANEL_TARGET_DEFAULT, problem: null };
  if (typeof raw === "string" && PANEL_TARGETS.indexOf(raw) >= 0) return { target: raw, problem: null };
  return {
    target: PANEL_TARGET_DEFAULT,
    problem: 'ermine.preview.target is one of "panel", "json" or "both", not ' +
      (typeof raw === "string" ? JSON.stringify(raw) : "a " + typeName(raw)) +
      '; the preview uses "' + PANEL_TARGET_DEFAULT + '"',
  };
}

/**
 * The design review's W5 / §2(g) option 1: the reducer has no fast-mode state
 * and gets no tenth kind; the sentence §5's Errors row wants is composed HERE,
 * into the `error` message, from the same `fastMode` read `extension.js`
 * already makes.
 */
const FAST_MODE_SUFFIX = " -- fast mode is on: type errors are not shown in Problems";
/** The reducer's own ERROR_DEFAULT; used so a blank message plus the suffix
 *  never becomes a banner that says ONLY the suffix. */
const PANEL_ERROR_DEFAULT = "the render failed";

/** What the panel has been told about answers: the LAST current one, and the
 *  last GOOD one (the reducer keeps the last document below an error, so a
 *  snapshot must be able to re-send it). */
function initialPanelAnswers() {
  return { last: null, good: null };
}

/**
 * One render outcome folded into the panel's answers.  `outcome` is exactly
 * one of `{answer}` (what `sendRequest` resolved with, or a params refusal)
 * and `{rejection, generation}` (what it rejected with, and the generation of
 * the render that sent it).  `current` is the extension's generation NOW.
 *
 * THE SAME THREE DECISIONS `renderNow` makes, in its order, by the same
 * functions: a displaced render (`isDisplaced`, -32800) changes NOTHING; any
 * other rejection is dressed by `errorAnswer`; an answer behind `current` is
 * discarded (`isCurrentGeneration`, section 2.5).  Returns `answers` BY
 * IDENTITY whenever nothing is to be shown, so a caller can compare.
 */
function panelAnswerStep(answers, outcome, current) {
  const a = answers || initialPanelAnswers();
  if (!outcome || typeof outcome !== "object") return a;
  let answer;
  if (Object.prototype.hasOwnProperty.call(outcome, "rejection")) {
    if (isDisplaced(outcome.rejection)) return a;
    answer = errorAnswer(outcome.rejection, outcome.generation);
  } else {
    answer = outcome.answer;
  }
  if (!answer || typeof answer !== "object") return a;
  if (!isCurrentGeneration(current, answer)) return a;
  return { last: answer, good: isOk(answer) ? answer : a.good };
}

/**
 * §5's Unsaved row: the dirty Ermine documents, by base name, sorted and
 * de-duplicated.  `documents` is what the glue maps `workspace.textDocuments`
 * to -- `{fileName, isDirty, languageId}` each -- so nothing here knows the
 * editor.  W6: NOT WIRED IN S2 either -- nothing produces it yet; open.
 */
function unsavedNames(documents) {
  const out = new Set();
  for (const d of Array.isArray(documents) ? documents : []) {
    if (!d || d.isDirty !== true || d.languageId !== "ermine") continue;
    if (typeof d.fileName !== "string" || !d.fileName.trim()) continue;
    out.add(path.basename(d.fileName));
  }
  return Array.from(out).sort();
}

/**
 * THE SHARED BUILDER: the extension-side view the panel's messages are a
 * function of.  S2's glue calls this with its module globals and the tests
 * call it with theirs; `panelMessagesFor` reads nothing else.
 *
 *   answers        `panelAnswerStep`'s result (`initialPanelAnswers()` if none)
 *   stuckState     `stuckReduce`'s state (`initialStuckState()` if none) --
 *                  its `stuck`/`message`/`highWater` are the ARBITRATED wedge,
 *                  its `running` is the offline flag
 *   mark, pick,    WP-22's wedge mark, the current pick and whether WE
 *   restartedByUs  restarted the server -- handed to `heldMessage` unchanged
 *   pending        a render is scheduled or in flight (§5's Stale row)
 *   unsaved        `unsavedNames(...)`
 *   fastMode       `config().get("fastMode")`
 *   switching      ALWAYS null today: NO PRODUCER EXISTS (W6; profiles are
 *                  WP-13/14).  The slot is here so the snapshot still
 *                  overwrites the reducer's slice.
 *   reloading      a bundle reload was ANNOUNCED and `webview.html` has not
 *                  been re-set yet (S3's watcher)
 *
 * The result is a frozen plain object with no functions in it.
 */
function panelView(parts) {
  const p = parts || {};
  const answers = p.answers && typeof p.answers === "object" ? p.answers : initialPanelAnswers();
  const s = p.stuckState && typeof p.stuckState === "object" ? p.stuckState : initialStuckState();
  const held = heldMessage(p.mark, p.pick, p.restartedByUs === true);
  return Object.freeze({
    answer: answers.last && typeof answers.last === "object" ? answers.last : null,
    document: isOk(answers.good) ? answers.good : null,
    pending: p.pending === true,
    stuck: s.stuck === true
      ? Object.freeze({
          message: typeof s.message === "string" && s.message.trim() ? s.message : null,
          seq: typeof s.highWater === "number" && s.highWater > 0 ? s.highWater : null,
        })
      : null,
    held: typeof held === "string" && held ? held : null,
    offline: s.running === false,
    unsaved: Object.freeze(Array.isArray(p.unsaved) ? p.unsaved.filter((n) => typeof n === "string" && n.trim() !== "") : []),
    fastMode: p.fastMode === true,
    switching: typeof p.switching === "string" && p.switching.trim() ? p.switching : null,
    reloading: p.reloading === true,
  });
}

/** An `{ok:false}` answer as the reducer's `error` message, with W5's suffix. */
function panelErrorMessage(answer, fastMode) {
  const text = typeof answer.message === "string" && answer.message.trim() ? answer.message : PANEL_ERROR_DEFAULT;
  return {
    kind: "error",
    status: typeof answer.status === "number" && isFinite(answer.status) ? answer.status : 0,
    message: fastMode === true ? text + FAST_MODE_SUFFIX : text,
    path: typeof answer.path === "string" && answer.path.trim() ? answer.path : null,
    reason: typeof answer.reason === "string" && answer.reason.trim() ? answer.reason : null,
  };
}

/**
 * THE WHOLE PROTOCOL, extension -> panel: the ordered host-reducer messages
 * for a view built by `panelView`.  Order, and why:
 *
 *   1. `render` of the last GOOD document, if there is one;
 *   2. `error`, if the last current answer was not ok (it keeps the document
 *      from 1 below it, dimmed -- §5's Errors row);
 *   3. `stale` -- AFTER the answer pair, because both answers clear it: true
 *      when a render is pending or the last answer carried the server's own
 *      `stale: true` (§2.5's hint, read off the answer);
 *   4. `stuck`, `held`, `offline`, `switching`, `unsaved` -- every slice,
 *      always, both edges (the snapshot rule above).  `held` carries NO
 *      button: WP-22's Render anyway is the extension's `showWarningMessage`
 *      (U4, TAKEN: Restart only);
 *   5. `reloadBundle` LAST and only while announced: an answer clears it, so
 *      it must follow the answer pair or the snapshot would lose it.
 */
function panelMessagesFor(view) {
  const v = view && typeof view === "object" ? view : panelView({});
  const out = [];
  const good = v.document;
  if (isOk(good)) {
    out.push({
      kind: "render",
      document: good.document,
      generation: typeof good.generation === "number" && isFinite(good.generation) ? good.generation : null,
    });
  }
  const last = v.answer;
  if (last && typeof last === "object" && !isOk(last)) out.push(panelErrorMessage(last, v.fastMode));
  out.push({ kind: "stale", stale: v.pending === true || !!(last && typeof last === "object" && last.stale === true) });
  if (v.stuck) {
    const m = { kind: "stuck", stuck: true };
    if (v.stuck.message) m.message = v.stuck.message;
    if (typeof v.stuck.seq === "number") m.seq = v.stuck.seq;
    out.push(m);
  } else {
    out.push({ kind: "stuck", stuck: false });
  }
  out.push(typeof v.held === "string" && v.held ? { kind: "held", held: true, message: v.held } : { kind: "held", held: false });
  out.push({ kind: "offline", offline: v.offline === true });
  // W6: NOT WIRED.  `panelView` has no producer for it, so this is always
  // `{to: null}` today -- sent so a snapshot overwrites the slice.
  out.push({ kind: "switching", to: typeof v.switching === "string" && v.switching ? v.switching : null });
  out.push({ kind: "unsaved", names: Array.isArray(v.unsaved) ? v.unsaved.slice() : [] });
  if (v.reloading === true) out.push({ kind: "reloadBundle" });
  return out;
}

// ------------------------------------------------- the host page (WP-10, S1)

/** The id of the one element the page draws into. */
const PREVIEW_ROOT_ID = "ermine-preview-root";

/**
 * THE CSP, one line, character for character (design review §2(b)):
 * `'unsafe-eval'` is the user's Q19 decision (the writers bundle is a
 * webpack-4 eval build), in THIS webview only; NO nonce, because no inline
 * script remains (W3: `acquireVsCodeApi()` lives in the host bundle); no
 * `blob:` (U5, F3) and no `font-src` (F3); and `default-src 'none'` is what
 * keeps `connect-src` shut, which is F2's check that the preview never
 * minted a deferred token.
 */
function previewCsp(cspSource) {
  return "default-src 'none'; script-src " + cspSource + " 'unsafe-eval'; style-src " + cspSource +
    " 'unsafe-inline'; img-src " + cspSource + " data:;";
}

/** A `cspSource` that could break out of its directive is refused, not escaped. */
function cspSourceProblem(s) {
  if (typeof s !== "string" || !s.trim()) return "cspSource is not a non-empty string";
  if (/[\s;,'"<>&\\]/.test(s)) return "cspSource " + JSON.stringify(s) + " contains a character that would change the policy";
  return null;
}

function htmlEscape(s) {
  return String(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** `?v=<stamp>` (or `&v=`) -- the cache-buster S3's reload needs, and what
 *  makes a re-set `webview.html` differ from the last one. */
function withStamp(uri, stamp) {
  if (stamp === undefined || stamp === null || stamp === "") return uri;
  return uri + (uri.indexOf("?") >= 0 ? "&" : "?") + "v=" + encodeURIComponent(String(stamp));
}

/**
 * The host page's HTML.  `uris` are webview URIs as STRINGS (S2 calls
 * `asWebviewUri(...).toString()`):
 *
 *   cspSource   `webview.cspSource`                       required
 *   client      `client/dist/browser/ermine-client.js`    required
 *   host        `client/dist/browser/ermine-host.js`      required
 *   writers     the writers' `web/htmlwriter.js`          optional (WP-11 / S4)
 *   styles      up to the writers' three CSS files, in    optional (WP-11 / S4)
 *               order: common.css, htmlwriter.css, a theme
 *
 * `opts.stamp` is appended to the client and host URIs only.
 *
 * SCRIPT ORDER IS LOAD-BEARING: writers -> client -> host, plain classic
 * `<script src>`, no defer / async / module.  The writers assign
 * `window.ermine_htmlwriter` inside a `DOMContentLoaded` LISTENER, listeners
 * fire in registration order, so the host's own listener (script 3) runs after
 * the global exists (READ, `ermine-writers/writers/js/htmlwriter.js:10-13`;
 * UNOBSERVED in any browser).  NO INLINE SCRIPT BODY, ever: the CSP has no
 * nonce and the page's bootstrap is the host bundle's.  Every URI is
 * HTML-escaped.  Bad input THROWS a named Error; S2 checks the bundle exists
 * before it calls this, and a throw here is a bug to see, not a state.
 */
function buildPreviewHtml(uris, opts) {
  const u = uris || {};
  const o = opts || {};
  const bad = cspSourceProblem(u.cspSource);
  if (bad) throw new Error("buildPreviewHtml: " + bad);
  for (const key of ["client", "host"]) {
    if (typeof u[key] !== "string" || !u[key].trim()) throw new Error("buildPreviewHtml: the " + key + " script URI is missing");
  }
  if (u.writers !== undefined && u.writers !== null && (typeof u.writers !== "string" || !u.writers.trim())) {
    throw new Error("buildPreviewHtml: the writers script URI is not a non-empty string");
  }
  const styles = u.styles === undefined || u.styles === null ? [] : u.styles;
  if (!Array.isArray(styles) || styles.length > 3 || styles.some((s) => typeof s !== "string" || !s.trim())) {
    throw new Error("buildPreviewHtml: styles is at most three non-empty URI strings");
  }
  const scripts = [];
  if (typeof u.writers === "string") scripts.push(u.writers);
  scripts.push(withStamp(u.client, o.stamp), withStamp(u.host, o.stamp));
  return [
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    '<meta charset="utf-8">',
    '<meta http-equiv="Content-Security-Policy" content="' + previewCsp(u.cspSource) + '">',
    "<title>Ermine preview</title>",
  ]
    .concat(styles.map((s) => '<link rel="stylesheet" href="' + htmlEscape(s) + '">'))
    .concat(["</head>", "<body>", '<div id="' + PREVIEW_ROOT_ID + '"></div>'])
    .concat(scripts.map((s) => '<script src="' + htmlEscape(s) + '"></script>'))
    .concat(["</body>", "</html>", ""])
    .join("\n");
}

// ------------------------------------------ the panel glue's pure half (WP-10, S2)
//
// S2 WIRES THE PANEL (`extension.js`: `openPanel`, `postSnapshot`,
// `onPanelMessage`, `present`), and every decision that glue makes is one of
// the functions below, so the models in test/preview-core.test.js call exactly
// what the glue calls (the rule at the head of that file):
//
//   * what is posted          `panelSnapshot(view, seq)` -- ONE shape, ever;
//   * what a panel message is `panelInbound(msg)`;
//   * where an answer goes    `presentRoute(target)` (U1);
//   * is the bundle there     `previewBundleDir(root)` + `previewBundleCheck`,
//                             over an fs LISTING the glue reads, fail-closed;
//   * what a missing bundle   `buildPanelNoticeHtml(check)`, static and
//     looks like              script-free.

/** `createWebviewPanel`'s viewType and title.  ONE panel per window. */
const PANEL_VIEW_TYPE = "ermine.preview";
const PANEL_TITLE = "Ermine preview";

/**
 * THE ONE MESSAGE THE EXTENSION POSTS TO THE PANEL: a whole-state envelope
 *
 *     { kind: "snapshot", seq, messages: panelMessagesFor(view) }
 *
 * never a loose host message.  The S1 finding that makes this binding: the
 * reducer's `reloading` is lowered ONLY by an answer, so loose posting diverges
 * from the truth when a reload is announced and abandoned before the first
 * answer; a snapshot folded from a fresh state cannot (`client/src/host/
 * page.ts` `receive`).  The discriminant is `kind`, NOT `type`: the envelope
 * travels in the same channel as, and is told apart from, the nine host
 * reducer kinds, which is `page.ts`'s committed S1 contract.  `seq` rises by one
 * per post; the page ignores an envelope whose `seq` is not above the last one
 * it applied, because `postMessage` ordering is documented neither way.
 */
function panelSnapshot(view, seq) {
  if (typeof seq !== "number" || !Number.isInteger(seq) || seq < 1) {
    throw new Error("panelSnapshot: seq is a positive integer, not " + JSON.stringify(seq));
  }
  return { kind: "snapshot", seq, messages: panelMessagesFor(view) };
}

/** Panel -> extension.  The panel DECIDES NOTHING: it announces itself, asks
 *  for the one action U4 allows, or hands the output channel a line. */
const PANEL_LOG_MAX = 2000;

function panelInbound(msg) {
  const ignore = (why) => ({ act: "ignore", why });
  if (!msg || typeof msg !== "object") return ignore("not an object");
  switch (msg.type) {
    case "ready":
      return { act: "ready" };
    case "intent":
      // U4, TAKEN: Restart ONLY.  The glue runs the `ermine.restartServer`
      // COMMAND -- the same door the stuck notification's button and the
      // palette use -- never `restart()` directly.
      if (msg.kind === "restartServer") return { act: "restartServer" };
      return ignore("an intent this extension does not offer: " + printable(msg.kind));
    case "log": {
      const text = typeof msg.message === "string" ? msg.message : printable(msg.message);
      return { act: "log", text: text.length > PANEL_LOG_MAX ? text.slice(0, PANEL_LOG_MAX) + "..." : text };
    }
    default:
      return ignore("an unknown message type " + printable(msg.type));
  }
}

/**
 * U1: where an answer is shown.  `json` is the WP-7/WP-8 tab alone and the tab
 * path is BYTE-IDENTICAL to 0.1.11's (playtest groups A and B are written
 * against it); `panel` is the panel alone; `both` is both.  An unknown target
 * is `panelTarget`'s to refuse; this takes what it answered.
 */
function presentRoute(target) {
  const t = PANEL_TARGETS.indexOf(target) >= 0 ? target : PANEL_TARGET_DEFAULT;
  return Object.freeze({ tab: t === "json" || t === "both", panel: t === "panel" || t === "both" });
}

/** The two entries webpack writes (`client/webpack.config.js`). */
const PREVIEW_BUNDLE_FILES = Object.freeze(["ermine-client.js", "ermine-host.js"]);

/**
 * U3, TAKEN: the bundle directory is DERIVED from `resolveServer().root` --
 * the checkout that already holds `bin/ermine-lsp` -- as
 * `<root>/client/dist/browser`.  `null` when there is no root at all.
 */
function previewBundleDir(root) {
  if (typeof root !== "string" || !root.trim()) return null;
  return path.join(root, "client", "dist", "browser");
}

/** `localResourceRoots`, as paths: exactly what the page loads.  The writers'
 *  `web/` directory is WP-11's slot (`ermine.preview.writersPath`, S4). */
function previewResourceRoots(bundleDir, writersDir) {
  const out = [];
  if (typeof bundleDir === "string" && bundleDir.trim()) out.push(bundleDir);
  if (typeof writersDir === "string" && writersDir.trim()) out.push(writersDir);
  return out;
}

/**
 * Is the bundle there, from a LISTING of `dir` (`fs.readdirSync`'s names, or
 * null when the directory could not be read).  FAIL-CLOSED: `ok` only when BOTH
 * entries are listed.  Four states:
 *
 *   ok       both present;
 *   no-root  no checkout to look in (no workspace folder, no serverPath);
 *   absent   neither present, or the directory is not there -- W10: THE
 *            DEFAULT FIRST EXPERIENCE, since `client/dist/` is git-ignored;
 *   half     one present and not the other -- LOUDER, the same rule as
 *            `client/test/bundle.test.ts`'s `skipWhenAbsent`: a half-written
 *            directory is a failure, not an absence.
 */
function previewBundleCheck(dir, listing) {
  const files = PREVIEW_BUNDLE_FILES.slice();
  if (typeof dir !== "string" || !dir.trim()) {
    return Object.freeze({
      ok: false, state: "no-root", dir: null, present: [], missing: files,
      title: "The preview cannot find its client bundle",
      message: "there is no workspace folder and ermine.serverPath is not set, so there is no checkout to find " +
        "client/dist/browser in",
    });
  }
  const names = Array.isArray(listing) ? listing.filter((n) => typeof n === "string") : [];
  const present = files.filter((f) => names.indexOf(f) >= 0);
  const missing = files.filter((f) => names.indexOf(f) < 0);
  if (missing.length === 0) {
    return Object.freeze({ ok: true, state: "ok", dir, present, missing, title: null, message: null });
  }
  const client = path.dirname(path.dirname(dir));
  if (present.length === 0) {
    return Object.freeze({
      ok: false, state: "absent", dir, present, missing,
      title: "The preview bundle is not built",
      message: "no " + files.join(" or ") + " in " + dir + ". Run `npm install` once and then `npm run bundle` in " +
        client + ", then run Ermine: Preview Report... again",
    });
  }
  return Object.freeze({
    ok: false, state: "half", dir, present, missing,
    title: "The preview bundle is HALF-BUILT",
    message: dir + " has " + present.join(", ") + " but not " + missing.join(", ") +
      ". Delete " + dir + " and run `npm run bundle` in " + client + ", then run Ermine: Preview Report... again",
  });
}

/**
 * The panel's page when there is no page to load: STATIC, SCRIPT-FREE, and
 * needing no resource root.  This IS the banner -- not a snapshot `error` --
 * because without `ermine-host.js` nothing in the page could fold a snapshot:
 * no script runs, so no `ready` is ever posted and the extension never posts
 * (the ready latch).  The CSP allows the inline `<style>` and nothing else.
 * `notice` is `previewBundleCheck`'s answer, or any `{title, message}`.
 */
function buildPanelNoticeHtml(notice) {
  const n = notice || {};
  const title = typeof n.title === "string" && n.title ? n.title : "The preview cannot be shown";
  const message = typeof n.message === "string" && n.message ? n.message : "";
  const kind = typeof n.state === "string" && n.state ? n.state : "problem";
  return [
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    '<meta charset="utf-8">',
    '<meta http-equiv="Content-Security-Policy" content="' + PANEL_NOTICE_CSP + '">',
    "<title>Ermine preview</title>",
    "<style>body{font-family:var(--vscode-font-family);color:var(--vscode-foreground);" +
      "background:var(--vscode-editor-background);padding:1em}" +
      ".ermine-banner{border-left:4px solid var(--vscode-editorError-foreground,#c33);padding:.5em 1em}" +
      "code{font-family:var(--vscode-editor-font-family)}</style>",
    "</head>",
    "<body>",
    '<div id="' + PREVIEW_ROOT_ID + '">',
    '<div class="ermine-banner" data-state="' + htmlEscape(kind) + '" role="alert">',
    "<strong>" + htmlEscape(title) + "</strong>",
    "<p>" + htmlEscape(message) + "</p>",
    "</div>",
    "</div>",
    "</body>",
    "</html>",
    "",
  ].join("\n");
}

/** The notice page's CSP: the inline style block, nothing else at all. */
const PANEL_NOTICE_CSP = "default-src 'none'; style-src 'unsafe-inline';";

// ------------------------------------------- the bundle watcher (WP-10, S3)
//
// `extension.js` watches the bundle FOLDER (`previewBundleDir`, U3) with the
// glob `*.js` -- the documented out-of-workspace form, `createFileSystemWatcher(
// new RelativePattern(Uri.file(dir), "*.js"))` -- and hands every create,
// change and delete, built by `bundleWatchEvent`, to `bundleWatchStep` with
// `Date.now()`.  W4: ONE webpack build writes FOUR files (two `.js`, two
// `.js.map`) and each `.js` may be reported more than once, so the step is a
// COALESCER over the whole folder, not per file: every event pushes ONE shared
// deadline `BUNDLE_QUIET_MS` further out, and only a quiet period with no
// event at all reloads -- once, however many files moved.
//
// What the glue does with the effects, and nothing else:
//   armMs     (re)arm its ONE timer for that many ms; the timer's callback is
//             `{type: "timer", at: Date.now()}` back into this step;
//   announce  the FIRST event of a burst: post a snapshot, whose view now says
//             `reloading` (`bundleReloading`), so the page that is about to be
//             replaced shows the reducer's own `reloadBundle` banner;
//   reload    the burst is over: re-check the bundle (`previewBundleCheck`) and
//             re-set `webview.html` -- the page with a fresh stamp when it is
//             whole, the static notice page when it is gone or half-built (H4),
//             and the page again when it comes back.  The ready latch drops and
//             the new page's `ready` brings the snapshot (with `reloading`
//             false: the state is idle again by then);
//   disarm    clear the timer (the panel is gone).
//
// The step never sees the editor and never reads the disk; the clock is an
// argument, so the models in test/preview-core.test.js drive it with a fake one.

/** The glob the watcher is created with -- the `.js.map` files do not match. */
const BUNDLE_WATCH_GLOB = "*.js";
/** W4: >= 200 ms.  One webpack build's writes land well inside it (INFERRED:
 *  webpack's write atomicity is UNVERIFIED -- a burst that straddles it costs a
 *  second reload, and a half-written directory in between is the HALF-BUILT
 *  notice for that moment, never a broken page). */
const BUNDLE_QUIET_MS = 250;
/** The three watcher events, by the names the glue's three arms pass. */
const BUNDLE_WATCH_KINDS = Object.freeze(["create", "change", "delete"]);

/** THE SHARED BUILDER for what the glue passes: the watcher arm's kind and the
 *  event's `uri.fsPath`, reduced to the file's base name. */
function bundleWatchEvent(kind, fsPath) {
  return Object.freeze({
    kind: typeof kind === "string" ? kind : String(kind),
    file: typeof fsPath === "string" && fsPath ? path.basename(fsPath) : null,
  });
}

function initialBundleWatch() {
  return Object.freeze({ due: null, events: 0, files: Object.freeze([]) });
}

/** Is a reload announced and not yet done -- `panelView`'s `reloading`. */
function bundleReloading(state) {
  return !!state && typeof state === "object" && typeof state.due === "number";
}

const NO_BUNDLE_EFFECTS = Object.freeze({ armMs: null, announce: false, reload: false, disarm: false, events: 0, files: Object.freeze([]) });

/**
 * One input into the watcher's state:
 *
 *   {type: "event", event: bundleWatchEvent(..), at}   a watcher arm fired
 *   {type: "timer", at}                                the one timer fired
 *   {type: "dispose"}                                  the panel went away
 *
 * An event that is not one of the three kinds, or names no `.js` file, is
 * IGNORED by identity (a `.js.map` never reaches here through the glob; the
 * filter is the same rule said twice).  A timer that fires before the deadline
 * -- a clock that stepped -- re-arms for the rest.  Returns `{state, effects}`.
 */
function bundleWatchStep(state, input) {
  const s = state && typeof state === "object" ? state : initialBundleWatch();
  const same = { state: s, effects: NO_BUNDLE_EFFECTS };
  if (!input || typeof input !== "object") return same;
  if (input.type === "dispose") {
    return { state: initialBundleWatch(), effects: Object.freeze(Object.assign({}, NO_BUNDLE_EFFECTS, { disarm: true })) };
  }
  const at = typeof input.at === "number" && isFinite(input.at) ? input.at : null;
  if (at === null) return same;
  if (input.type === "event") {
    const e = input.event;
    if (!e || BUNDLE_WATCH_KINDS.indexOf(e.kind) < 0 || typeof e.file !== "string" || !/\.js$/.test(e.file)) return same;
    const files = s.files.indexOf(e.file) >= 0 ? s.files : Object.freeze(s.files.concat([e.file]).sort());
    return {
      state: Object.freeze({ due: at + BUNDLE_QUIET_MS, events: s.events + 1, files }),
      effects: Object.freeze(Object.assign({}, NO_BUNDLE_EFFECTS, { armMs: BUNDLE_QUIET_MS, announce: s.due === null })),
    };
  }
  if (input.type === "timer") {
    if (s.due === null) return same;
    if (at < s.due) return { state: s, effects: Object.freeze(Object.assign({}, NO_BUNDLE_EFFECTS, { armMs: s.due - at })) };
    return {
      state: initialBundleWatch(),
      effects: Object.freeze(Object.assign({}, NO_BUNDLE_EFFECTS, { reload: true, events: s.events, files: s.files })),
    };
  }
  return same;
}

/** The one output-channel line a reload writes: what the page was, what it is
 *  now.  `before` is the check the page was last built from (or null), `after`
 *  the fresh one. */
function bundleReloadLine(before, after, events) {
  const n = typeof events === "number" && events > 0 ? events : 0;
  const why = "the client bundle changed (" + n + " file event" + (n === 1 ? "" : "s") + ")";
  const a = after && typeof after === "object" ? after : { ok: false, title: "no bundle check" };
  if (a.ok) {
    return before && before.ok
      ? "preview: " + why + "; reloading the panel"
      : "preview: " + why + " and the bundle is whole again; loading the panel page";
  }
  return "preview: " + why + " and the bundle is not whole (" + (a.state || "problem") + "); showing the notice page";
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
  markParamsFor,
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
  // WP-8 S2: the decisions the SENDING glue makes, still pure.
  paramsFolderFor,
  meansFileMissing,
  renderAttempt,
  previewNow,
  renderRequest,
  mayStillSend,
  paramsRefusalAnswer,
  paramsNoticeKey,
  paramsMissingNotice,
  paramsTooLargeToRead,
  paramsReadTimedOut,
  PARAMS_READ_TIMEOUT_MS,
  ABANDON_REASONS,
  TRIGGER_EXPLICIT,
  TRIGGER_PARAMS_FILE,
  TRIGGER_MODULE_LEARNED,
  TRIGGER_INVALIDATED,
  TRIGGER_FILE_EVENT,
  TRIGGER_ROOTS,
  TRIGGER_RECOVERED,
  TRIGGER_ANSWER,
  TRIGGER_SCHEMA,
  RENDER_TRIGGERS,
  UNCONFIRMED_TRIGGERS,
  isRenderTrigger,
  triggerProblem,
  markMintedAfter,
  mayAutoRender,
  heldPromptToken,
  shouldAskHeld,
  isCurrentSchemaAnswer,
  skeletonFrom,
  schemaFileFor,
  schemaFileText,
  paramsToSend,
  credentialKeyWarning,
  paramsGitignoreText,
  // WP-8 S3: the first `ermine/schema` client, and the first writes.
  isoDay,
  schemaOrder,
  shouldRefreshSchema,
  schemaOutcome,
  schemaAnswerOutcome,
  schemaRequestFailure,
  schemaFileBytes,
  firstPickResult,
  writeResult,
  mayUseSchemaAnswer,
  schemaFileNeedsWrite,
  paramsWritePlan,
  paramsWrittenNotice,
  schemaProblemNotice,
  schemaNoticeKey,
  SCHEMA_REFRESH_TRIGGERS,
  // S3 review M-1: the shapes the glue hands its own decisions, minted once.
  preparedParams,
  PREPARED_PATH_PROBLEM,
  PREPARED_MISSING,
  PREPARED_READ,
  PREPARED_REFUSAL,
  PREPARED_KINDS,
  createOutcome,
  writeOutcome,
  writeFailedProblem,
  schemaAbandoned,
  CREATED,
  EXISTED,
  CREATE_FAILED,
  // S3 review M-2: the plan's vocabulary, and the fail-CLOSED step decision.
  WRITE_IF_ABSENT,
  WRITE_IF_DIFFERENT,
  WRITE_GITIGNORE,
  WRITE_SCHEMA,
  WRITE_PARAMS,
  writeStep,
  // WP-8 S4: U3's command, D6's orphan notice, and what a non-object root is.
  WRITE_EXPLICIT_OVERWRITE,
  skeletonCommandPlan,
  paramsRootShape,
  rootShapeSentence,
  SKELETON_COMMAND,
  SKELETON_REPLACE,
  skeletonCommandVerdict,
  skeletonConfirmation,
  skeletonConfirmed,
  skeletonStillApplies,
  skeletonReplacedNotice,
  skeletonWrittenNotice,
  claimParamsDocument,
  skeletonBytesStillApply,
  skeletonCommandResult,
  directoryListing,
  orphanParamsFiles,
  orphanNoticeKey,
  orphanNoticeText,
  orphanListingNotice,
  orphanNoticePlan,
  ORPHAN_BUTTON,
  FILE_TYPE_FILE,
  PARAMS_SUFFIX,
  // S3 review M-3: symlinks.
  FILE_TYPE_SYMLINK,
  writeTargetPaths,
  writeTargetProblem,
  PARAMS_MAX_BYTES,
  CREDENTIAL_KEY,
  NIL_UUID,
  MAX_NAME_LENGTH,
  MAX_SKELETON_DEPTH,
  RESERVED_DEVICE_NAMES,
  // WP-10 S1: the panel's pure half -- nothing of it is wired yet.
  PANEL_MESSAGE_KINDS,
  PANEL_TARGETS,
  PANEL_TARGET_DEFAULT,
  panelTarget,
  FAST_MODE_SUFFIX,
  initialPanelAnswers,
  panelAnswerStep,
  unsavedNames,
  panelView,
  panelMessagesFor,
  PREVIEW_ROOT_ID,
  previewCsp,
  buildPreviewHtml,
  // WP-10 S2: the glue's decisions, shared with the models.
  PANEL_VIEW_TYPE,
  PANEL_TITLE,
  panelSnapshot,
  panelInbound,
  presentRoute,
  PREVIEW_BUNDLE_FILES,
  previewBundleDir,
  previewResourceRoots,
  previewBundleCheck,
  buildPanelNoticeHtml,
  PANEL_NOTICE_CSP,
  // WP-10 S3: the bundle watcher's coalescer.
  BUNDLE_WATCH_GLOB,
  BUNDLE_QUIET_MS,
  BUNDLE_WATCH_KINDS,
  bundleWatchEvent,
  initialBundleWatch,
  bundleReloading,
  bundleWatchStep,
  bundleReloadLine,
};
