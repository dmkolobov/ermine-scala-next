// The browser bundle (WP-9).  `client/webpack.config.js` -> `dist/browser/`.
//
// These are the two rows of §5's bundle checklist that jsdom CAN answer (the
// design review's D9), plus the one that says the bundled client and the
// CommonJS one are the same code:
//
//   (i)   neither output contains `eval(` or `new Function`.  That is the STATIC
//         half of "loads under a webview CSP without 'unsafe-eval'", and it is
//         exactly the check that would have caught Q19 in the committed
//         ermine-writers bundle (574 `eval("` module wrappers, MEASURED).
//         `mode: 'development'` DEFAULTS to `devtool: 'eval'`, so this test is
//         what pins `devtool: 'source-map'` in the config.
//   (ii)  loaded into a JSDOM, `window.ErmineClient` exposes EXACTLY the names
//         `client/src/index.ts` exports.  The expected list is READ OFF THE
//         MODULE, never written out here, so adding an export cannot make the
//         two drift apart silently.
//   (iii) the same document rendered through `window.ErmineClient` and through
//         the CommonJS build produces the same DOM.
//
// The third checklist row -- "`table` renders through the writers global" --
// stays HUMAN: it needs the real writers bundle in a real browser, and jsdom
// does not enforce a CSP.  NOTHING HERE HAS RUN IN A BROWSER OR A WEBVIEW.
//
// Absent bundle: these SKIP, naming `npm run bundle`, the same convention the
// three fixture tests use.  `npm test` is therefore still green from a clean
// checkout, and `npm run test:bundle` builds first.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as path from "path";
import { JSDOM } from "jsdom";

import * as client from "../src/index";
import * as host from "../src/host/index";
import * as page from "../src/host/page";

// dist/test -> dist -> dist/browser, where webpack writes
const BROWSER = path.resolve(__dirname, "../browser");
const CLIENT_JS = path.join(BROWSER, "ermine-client.js");
const HOST_JS = path.join(BROWSER, "ermine-host.js");

const MISSING = `no bundle at ${BROWSER} -- run \`npm run bundle\` (or \`npm run test:bundle\`)`;

/** Through JSON.  Values a bundle mints live in the JSDOM realm, so their
 *  prototype is not this realm's and `deepStrictEqual`, which compares
 *  prototypes, refuses two structurally identical objects. */
function plain(v: unknown): unknown { return JSON.parse(JSON.stringify(v)); }

const ENTRIES = [CLIENT_JS, HOST_JS];

/** Skip only when the bundle is wholly ABSENT.  A HALF-written `dist/browser`
 *  -- one entry present, the other not -- is a FAILURE: `npm test` against a
 *  leftover directory would otherwise report "no bundle, run npm run bundle"
 *  and exit 0 while half a bundle sat on disk (nit N-1 of the WP-9 review). */
function skipWhenAbsent(t: { skip(m: string): void }): boolean {
  const present = ENTRIES.filter((f) => fs.existsSync(f));
  if (present.length === ENTRIES.length) return false;
  if (present.length === 0) { t.skip(MISSING); return true; }
  const missing = ENTRIES.filter((f) => !fs.existsSync(f)).map((f) => path.basename(f));
  throw new Error(
    `dist/browser is HALF-BUILT: ${present.map((f) => path.basename(f)).join(", ")} present, ` +
    `${missing.join(", ")} missing. Delete dist/browser and run \`npm run bundle\`.`);
}

/** A JSDOM with scripts enabled, with the bundle evaluated in it. */
function domWith(...bundles: string[]): JSDOM {
  const dom = new JSDOM(
    "<!doctype html><html><body><div id='bundle'></div><div id='cjs'></div></body></html>",
    { runScripts: "dangerously" });
  for (const b of bundles) {
    const el = dom.window.document.createElement("script");
    el.textContent = fs.readFileSync(b, "utf8");
    dom.window.document.head.appendChild(el);
  }
  return dom;
}

// the (w-scorecard) fixture, as a STRING: parsed inside whichever realm renders
// it, so nothing crosses a realm boundary except the DOM itself
const FIXTURE = JSON.stringify({
  version: 1,
  settings: {},
  root: {
    tag: "VFlow",
    children: [
      {
        tag: "Widget", name: "scorecard",
        props: {
          title: "Sales by region", cardLabel: "region", cardValue: "sales",
          cardDelta: "sales",
          cardFormat: { tag: "Round", color: false, negParens: false, places: 1 },
          cards: {
            kind: "inline",
            columns: [{ name: "region", type: "String", nullable: false },
                      { name: "sales", type: "Double", nullable: true }],
            rows: [["EMEA", 120.55], ["APAC", null], ["AMER", -3]],
            rowCount: 3,
          },
        },
      },
      {
        tag: "Widget", name: "headline",
        props: {
          headlineTitle: "This quarter", scope: "in EMEA",
          rowCount: 3, total: 117.55, largest: 120.55,
          headlineFormat: { tag: "Currency", color: false, negParens: false, symbol: "$", places: 2 },
        },
      },
    ],
  },
});

// ------------------------------------------------------------------- (i) CSP

test("(b-no-eval) neither bundle contains `eval(` or `new Function`", (t) => {
  if (skipWhenAbsent(t)) return;
  for (const f of [CLIENT_JS, HOST_JS]) {
    const src = fs.readFileSync(f, "utf8");
    const evals = src.match(/eval\s*\(/g) ?? [];
    const fns = src.match(/new\s+Function\b/g) ?? [];
    assert.deepStrictEqual(evals, [],
      `${path.basename(f)} has ${evals.length} eval( -- a webview CSP without 'unsafe-eval' blocks every one. ` +
      `Check webpack.config.js's devtool: mode 'development' defaults to 'eval'.`);
    assert.deepStrictEqual(fns, [], `${path.basename(f)} has ${fns.length} new Function -- the same CSP forbids it`);
  }
});

test("(b-sourcemap) a separate .map sits beside each bundle and the bundle points at it", (t) => {
  if (skipWhenAbsent(t)) return;
  for (const f of [CLIENT_JS, HOST_JS]) {
    assert.ok(fs.existsSync(`${f}.map`), `${path.basename(f)}.map`);
    const src = fs.readFileSync(f, "utf8");
    assert.match(src, new RegExp(`sourceMappingURL=${path.basename(f)}\\.map\\s*$`),
      "the map is a separate FILE, not an inline data: URI -- an inline one would be an eval-flavoured devtool");
    const map = JSON.parse(fs.readFileSync(`${f}.map`, "utf8")) as { sources: string[] };
    assert.ok(map.sources.length > 0);
  }
});

// -------------------------------------------------------------- (ii) surface

test("(b-surface) window.ErmineClient exposes exactly what src/index.ts exports", (t) => {
  if (skipWhenAbsent(t)) return;
  const dom = domWith(CLIENT_JS);
  const exposed = dom.window as unknown as { ErmineClient?: Record<string, unknown> };
  assert.ok(exposed.ErmineClient, "window.ErmineClient");
  // the expected list is the MODULE's own, never a hand-written copy
  const want = Object.keys(client).sort();
  assert.ok(want.length > 20, `sanity: src/index.ts exports ${want.length} names`);
  assert.deepStrictEqual(Object.keys(exposed.ErmineClient!).sort(), want);
  // and the two names §5's checklist actually names are callable
  assert.equal(typeof exposed.ErmineClient!["parseDocument"], "function");
  assert.equal(typeof exposed.ErmineClient!["render"], "function");
  assert.equal(typeof exposed.ErmineClient!["defaultRegistry"], "function");
  dom.window.close();
});

test("(b-host-surface) window.ErmineHost exposes exactly what src/host/page.ts exports -- the reducer's whole surface included -- and agrees with it", (t) => {
  if (skipWhenAbsent(t)) return;
  const dom = domWith(HOST_JS);
  const exposed = (dom.window as unknown as { ErmineHost?: Record<string, unknown> }).ErmineHost;
  assert.ok(exposed, "window.ErmineHost");
  // WP-10 S2: the entry is `host/page` (the bootstrap), which re-exports the reducer
  assert.deepStrictEqual(Object.keys(exposed!).sort(), Object.keys(page).sort());
  for (const k of Object.keys(host)) assert.ok(k in exposed!, `the reducer's ${k} is still exposed`);

  // the host entry carries NO zod, and that is a property of the panel, not an
  // accident: `src/host/` imports nothing, so the reducer bundle is ~10 KB while
  // zod alone is 154 KiB of the client's 319 KiB.  The day WP-10 adds
  // `import … from "../document"` this goes red rather than silently doubling
  // the bytes a webview loads (nit N-2 of the WP-9 review).
  const hostSrc = fs.readFileSync(HOST_JS, "utf8");
  assert.equal((hostSrc.match(/ZodError|ZodType|z\.object\(/g) ?? []).length, 0,
    "zod reached ermine-host.js -- src/host/ must import nothing");
  assert.ok(hostSrc.length < 64 * 1024,
    `ermine-host.js is ${hostSrc.length} B; the reducer alone is ~10 KB, so something was pulled in`);

  // the bundled reducer and the CommonJS one fold the same sequence the same way
  const apply = exposed!["applyMessage"] as typeof host.applyMessage;
  const init = exposed!["initialHostState"] as typeof host.initialHostState;
  const present = exposed!["presentation"] as typeof host.presentation;
  const msgs: host.HostMessage[] = [
    { kind: "render", document: { root: 1 }, generation: 4 },
    { kind: "stale", stale: true },
    { kind: "error", status: 400, message: "bad param", path: "$.params.from" },
    { kind: "stuck", stuck: true, message: "did not finish", seq: 2 },
    { kind: "held", held: true },
    { kind: "unsaved", names: ["Sales.e"] },
  ];
  assert.deepStrictEqual(plain(present(msgs.reduce(apply, init()))),
                         plain(host.presentation(msgs.reduce(host.applyMessage, host.initialHostState()))));
  dom.window.close();
});

// ------------------------------------------------------------------- (iii) DOM

test("(b-same-dom) a document rendered through the bundle matches the CommonJS build", async (t) => {
  if (skipWhenAbsent(t)) return;
  const dom = domWith(CLIENT_JS);
  const document = dom.window.document as unknown as Document;
  const refuse = async (token: string): Promise<never> => { throw new Error(`nothing is deferred here (${token})`); };

  // the bundle's realm, parsing its own copy of the fixture
  const bundled = (dom.window as unknown as { ErmineClient: typeof client }).ErmineClient;
  const bundleResult = await bundled.render(
    document.getElementById("bundle")!, bundled.parseDocument(FIXTURE), bundled.defaultRegistry(),
    { document, fetchData: refuse });

  // the CommonJS build, into the SAME document
  const cjsResult = await client.render(
    document.getElementById("cjs")!, client.parseDocument(FIXTURE), client.defaultRegistry(),
    { document, fetchData: refuse });

  assert.deepStrictEqual(plain(bundleResult.errors), [], "the bundle rendered without an error box");
  assert.deepStrictEqual(cjsResult.errors, []);
  assert.equal(document.getElementById("bundle")!.innerHTML,
               document.getElementById("cjs")!.innerHTML);
  // and it is a real render, not two empty divs
  assert.ok(document.querySelectorAll("#bundle section.ermine-scorecard .ermine-scorecard-card").length === 3);
  dom.window.close();
});

// ------------------------------------------------------ (iv) the panel page

test("(b-host-boot) the host bundle boots itself where acquireVsCodeApi exists: ready once, a snapshot renders, a toggle does not", async (t) => {
  if (skipWhenAbsent(t)) return;
  const dom = new JSDOM(
    `<!doctype html><html><head></head><body><div id="${page.PREVIEW_ROOT_ID}"></div></body></html>`,
    { runScripts: "dangerously" });
  const w = dom.window as unknown as Record<string, unknown>;
  const posted: unknown[] = [];
  let acquired = 0;
  w["acquireVsCodeApi"] = () => { acquired += 1; return { postMessage: (m: unknown) => posted.push(JSON.parse(JSON.stringify(m))) }; };
  for (const b of [CLIENT_JS, HOST_JS]) {
    const el = dom.window.document.createElement("script");
    el.textContent = fs.readFileSync(b, "utf8");
    dom.window.document.body.appendChild(el);
  }
  assert.equal(acquired, 1, "acquireVsCodeApi is called ONCE");
  assert.deepStrictEqual(posted, [], "nothing before DOMContentLoaded");
  if (dom.window.document.readyState === "loading") {
    await new Promise((r) => dom.window.document.addEventListener("DOMContentLoaded", r));
  }
  assert.deepStrictEqual(posted, [{ type: "ready" }]);
  const send = async (env: unknown): Promise<void> => {
    dom.window.dispatchEvent(new dom.window.MessageEvent("message", { data: env }));
    await new Promise((r) => setTimeout(r, 20));
  };
  const render = { kind: "render", document: JSON.parse(FIXTURE), generation: 1 };
  await send({ kind: "snapshot", seq: 1, messages: [render, { kind: "stale", stale: false }] });
  const area = dom.window.document.querySelector(".ermine-document")!;
  assert.ok(area.querySelector(".ermine-scorecard"), "the scorecard rendered through window.ErmineClient: " + area.innerHTML.slice(0, 200));
  const node = area.firstElementChild;
  await send({ kind: "snapshot", seq: 2, messages: [render, { kind: "stale", stale: true }] });
  assert.equal(area.firstElementChild, node, "a stale toggle does not re-render");
  assert.equal(dom.window.document.querySelector(".ermine-banner")!.getAttribute("data-kind"), "stale");
  assert.equal(posted.length, 1, "and nothing was logged: no widget failed");
  dom.window.close();
});
