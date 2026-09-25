// The dispatcher: layout containers, the registry, relation resolution, and the
// error box that stands where a broken widget would be (property (d), the
// self-contained half; the corpus half is corpus.test.ts).

import { test } from "node:test";
import assert from "node:assert/strict";

import { parseDocument, safeParseDocument, DocumentError } from "../src/document";
import { render, errorBox, type Registry, type RenderEnv } from "../src/dispatcher";
import { defaultRegistry } from "../src/index";
import { resolveRelations, httpFetchData, type InlineRelation } from "../src/relation";
import { newDom, stubHtmlWriter, inlineRelation, refusingFetch } from "./harness";
import { mutateOnce } from "./mutate";

const rel = inlineRelation(
  [{ name: "region", type: "String" }, { name: "sales", type: "Double" }],
  [["EMEA", 120.5], ["APAC", -3]],
);

const tableProps = {
  columns: [
    { column: "region", header: "Region", cellFormat: { tag: "Default", args: [] }, align: "AlignLeft", kind: "OtherColumn" },
    { column: "sales", header: "Sales", cellFormat: { tag: "Round", color: false, negParens: false, places: 1 }, align: "AlignRight", kind: "NumberColumn" },
  ],
  sorts: [{ sortColumn: 1, descending: true }],
  paginate: true,
  scroll: false,
  rows: rel,
};

const scorecardProps = {
  title: "Sales",
  cardLabel: "region",
  cardValue: "sales",
  cardDelta: "sales",
  cardFormat: { tag: "IntegralRound", color: false, negParens: false, places: 0 },
  cards: rel,
};

function doc(root: unknown): unknown {
  return { version: 1, settings: {}, root };
}

function env(document: Document, fetchData = refusingFetch): RenderEnv {
  return { document, fetchData, htmlwriter: stubHtmlWriter() };
}

test("(d-envelope) parseDocument accepts v1 and refuses everything else with a path", () => {
  const good = doc({ tag: "Widget", name: "scorecard", props: scorecardProps });
  assert.equal(parseDocument(good).version, 1);
  assert.equal(parseDocument(JSON.stringify(good)).version, 1);
  for (const bad of [
    { version: 2, settings: {}, root: { tag: "VFlow", children: [] } },
    { version: 1, root: { tag: "VFlow", children: [] } },
    { version: 1, settings: {}, root: { tag: "VFlow", children: [] }, errors: [] },
    { version: 1, settings: {}, root: { tag: "Nope" } },
  ]) {
    const r = safeParseDocument(bad);
    assert.equal(r.ok, false, JSON.stringify(bad));
    if (!r.ok) assert.ok(r.error.message.length > 0 && r.error.issues.length > 0);
  }
  assert.throws(() => parseDocument("{"), DocumentError);
});

test("(d-layout) the four layout constructors build plain DOM containers", async () => {
  const { document, target } = newDom();
  const leaf = { tag: "Widget", name: "scorecard", props: scorecardProps };
  const root = {
    tag: "VFlow",
    children: [
      { tag: "HFlow", children: [leaf] },
      { tag: "Grid", cells: [[leaf], [leaf, leaf]] },
      { tag: "Tabbed", tabs: [{ label: "one", content: leaf }, { label: "two", content: leaf }] },
    ],
  };
  const result = await render(target, parseDocument(doc(root)), defaultRegistry(), env(document));
  assert.deepStrictEqual(result.errors, []);
  assert.equal(target.querySelectorAll(".ermine-vflow").length, 1);
  assert.equal(target.querySelectorAll(".ermine-hflow").length, 1);
  assert.equal(target.querySelectorAll(".ermine-grid-row").length, 2);
  assert.equal(target.querySelectorAll(".ermine-grid-cell").length, 3);
  assert.equal(target.querySelectorAll(".ermine-tab").length, 2);
  assert.equal(target.querySelectorAll(".ermine-scorecard").length, 6);
  // the first tab is showing, the second hidden; clicking swaps them
  const panels = target.querySelectorAll(".ermine-tab-panel");
  assert.equal(panels[0]?.hasAttribute("hidden"), false);
  assert.equal(panels[1]?.hasAttribute("hidden"), true);
  (target.querySelectorAll(".ermine-tab")[1] as HTMLElement).click();
  assert.equal(panels[0]?.hasAttribute("hidden"), true);
  assert.equal(panels[1]?.hasAttribute("hidden"), false);
});

test("(d-tab-shown) switching to a hidden tab runs the writers' resize once, or fires a window resize without it (WP-36)", async () => {
  const table = { tag: "Widget", name: "table", props: tableProps };
  const tabbed = doc({ tag: "Tabbed", tabs: [{ label: "one", content: table }, { label: "two", content: table }] });

  // with runResize: exactly one call per switch to a hidden tab, none for the active one
  {
    const { dom, document, target } = newDom();
    const hw = stubHtmlWriter();
    let resizes = 0;
    let events = 0;
    const withResize = { ...hw, runResize: (): void => { resizes++; } };
    dom.window.addEventListener("resize", () => { events++; });
    const result = await render(target, parseDocument(tabbed), defaultRegistry(), { document, fetchData: refusingFetch, htmlwriter: withResize });
    assert.deepStrictEqual(result.errors, []);
    assert.equal(hw.calls.length, 2, "both tabs' tables are drawn eagerly");
    assert.equal(resizes, 0, "nothing runs before a switch");
    const tabs = target.querySelectorAll(".ermine-tab");
    (tabs[1] as HTMLElement).click();
    assert.equal(resizes, 1, "the switch to tab two runs runResize exactly once");
    (tabs[1] as HTMLElement).click();
    assert.equal(resizes, 1, "clicking the tab already showing runs nothing");
    (tabs[0] as HTMLElement).click();
    assert.equal(resizes, 2);
    assert.equal(events, 0, "runResize present: no window event");
  }

  // without runResize: the window sees one resize event per switch
  {
    const { dom, document, target } = newDom();
    let events = 0;
    dom.window.addEventListener("resize", () => { events++; });
    await render(target, parseDocument(tabbed), defaultRegistry(), env(document));
    (target.querySelectorAll(".ermine-tab")[1] as HTMLElement).click();
    assert.equal(events, 1);
  }

  // a host's onShown replaces the default and is handed the panel now showing
  {
    const { document, target } = newDom();
    const shown: Element[] = [];
    await render(target, parseDocument(tabbed), defaultRegistry(), { ...env(document), onShown: (e) => shown.push(e) });
    (target.querySelectorAll(".ermine-tab")[1] as HTMLElement).click();
    assert.equal(shown.length, 1);
    assert.equal(shown[0]?.getAttribute("data-tab"), "1");
    assert.equal(shown[0]?.hasAttribute("hidden"), false, "called after un-hiding");
  }
});

test("(d-rerender-stale) after a re-render, a click on a never-visited tab builds the NEW render's rows only (WP-36 MF-1)", async () => {
  // A fake of the writers' contract (READ: tables.js:1375-1376, :1598;
  // ermine-htmlwriter.js:61, :2888): runTabular registers a build callback in a
  // page-global list; the callback looks its element up BY ID when it runs and
  // builds once, only if that element is visible; runResize runs every callback.
  const { document, target } = newDom();
  const callbacks: (() => void)[] = [];
  const builds: { render: string; id: string; rows: number }[] = [];
  let current = "";
  const fake = {
    runTabular(args: { id: string; relation: unknown[] }): void {
      const render = current;
      let built = false;
      callbacks.push(() => {
        const el = document.getElementById(args.id);
        if (built || !el || !el.isConnected || el.closest("[hidden]")) return;
        built = true;
        builds.push({ render, id: args.id, rows: args.relation.length });
      });
    },
    runResize(): void { for (const cb of callbacks) cb(); },
  };
  const two = inlineRelation(rel.columns, [["EMEA", 1], ["APAC", 2]]);
  const one = inlineRelation(rel.columns, [["LATAM", 3]]);
  const tabbed = (second: unknown) => doc({ tag: "Tabbed", tabs: [
    { label: "one", content: { tag: "Widget", name: "table", props: { ...tableProps, rows: two } } },
    { label: "two", content: { tag: "Widget", name: "table", props: { ...tableProps, rows: second } } },
  ] });
  const renderAs = async (name: string, second: unknown) => {
    current = name;
    const r = await render(target, parseDocument(tabbed(second)), defaultRegistry(), { document, fetchData: refusingFetch, htmlwriter: fake });
    assert.deepStrictEqual(r.errors, []);
    fake.runResize(); // the page's first draw builds what is visible
    return r;
  };
  const a = await renderAs("A", two);
  const b = await renderAs("B", one);
  assert.notEqual(a.idPrefix, b.idPrefix, "each render mints under its own prefix");
  builds.length = 0;
  (target.querySelectorAll(".ermine-tab")[1] as HTMLElement).click();
  assert.deepStrictEqual(builds.map((x) => [x.render, x.rows]), [["B", 1]],
    "only render B's table builds, with B's one row; never render A's two");
});

test("(d-unknown) an unregistered widget renders an error box and does not throw", async () => {
  const { document, target } = newDom();
  const result = await render(target, parseDocument(doc({ tag: "Widget", name: "axisChart", props: {} })),
    defaultRegistry(), env(document));
  assert.equal(result.errors.length, 1);
  assert.equal(result.errors[0]?.widget, "axisChart");
  const box = target.querySelector(".ermine-widget-error");
  assert.ok(box, "an error box stands where the chart would");
  assert.equal(box?.getAttribute("data-widget"), "axisChart");
  assert.match(box?.textContent ?? "", /axisChart/);
});

test("(d-prototype-names) `constructor`, `toString`, `__proto__` are unknown names: the registry's box, never the missing-schema one", async () => {
  // S2 review N-3: both lookups are own-property checks, so a name every object
  // literal inherits from Object.prototype is simply not a widget
  for (const name of ["constructor", "toString", "__proto__", "hasOwnProperty"]) {
    const { document, target } = newDom();
    const result = await render(target, parseDocument(doc({ tag: "Widget", name, props: {} })),
      defaultRegistry(), env(document));
    assert.deepStrictEqual(result.errors.map((e) => e.message), ["no renderer is registered under that name"], name);
    assert.equal(target.querySelectorAll(".ermine-widget-error").length, 1, name);
  }
});

test("(d-no-schema) a registry key with no generated schema says where to declare it (WP-32 S3)", async () => {
  // only a registry a JS caller built can carry a key WidgetRegistry lacks; the
  // message names the Ermine declaration and the generator, since no list exists
  const registry = { ...defaultRegistry(), gauge: { render: () => undefined } } as unknown as Registry;
  const { document, target } = newDom();
  const result = await render(target, parseDocument(doc({ tag: "Widget", name: "gauge", props: {} })),
    registry, env(document));
  assert.deepStrictEqual(result.errors.map((e) => e.message), [
    "no props schema was generated for it -- declare `xName : WidgetName (XProps r)` " +
      "in a Layout.Widgets module and run client/scripts/generate.sh",
  ]);
  assert.equal(target.querySelector(".ermine-widget-error")?.getAttribute("data-widget"), "gauge");
});

test("(d-invalid) invalid props render an error box naming the widget and the zod path", async () => {
  const { document, target } = newDom();
  const broken = { ...tableProps, columns: [{ ...tableProps.columns[0], align: "AlignSideways" }] };
  const result = await render(target, parseDocument(doc({ tag: "Widget", name: "table", props: broken })),
    defaultRegistry(), env(document));
  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0]?.message ?? "", /props are invalid/);
  assert.match(target.querySelector(".ermine-widget-error")?.textContent ?? "", /table/);
});

test("(d-throws) a renderer that throws is contained", async () => {
  const { document, target } = newDom();
  const registry: Registry = {
    ...defaultRegistry(),
    scorecard: { render(): void { throw new Error("boom"); } },
  };
  const result = await render(target, parseDocument(doc({ tag: "Widget", name: "scorecard", props: scorecardProps })),
    registry, env(document));
  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0]?.message ?? "", /threw while rendering: boom/);
  assert.ok(target.querySelector(".ermine-widget-error"));
});

test("(d-deferred) a deferred relation is fetched before the widget sees it", async () => {
  const { document, target } = newDom();
  const asked: string[] = [];
  const fetchData = async (token: string): Promise<InlineRelation> => {
    asked.push(token);
    return rel;
  };
  const deferred = {
    ...tableProps,
    rows: { kind: "deferred", columns: rel.columns, token: "abc123", expires: "2099-01-01T00:00:00.000Z" },
  };
  const hw = stubHtmlWriter();
  const result = await render(target, parseDocument(doc({ tag: "Widget", name: "table", props: deferred })),
    defaultRegistry(), { document, fetchData, htmlwriter: hw });
  assert.deepStrictEqual(result.errors, []);
  assert.deepStrictEqual(asked, ["abc123"]);
  assert.equal(hw.calls.length, 1);
  assert.equal(hw.calls[0]?.relation.length, 2);
});

test("(d-deferred-fails) a token that will not resolve becomes an error box, not an exception", async () => {
  const { document, target } = newDom();
  const deferred = {
    ...tableProps,
    rows: { kind: "deferred", columns: rel.columns, token: "gone", expires: "2099-01-01T00:00:00.000Z" },
  };
  const result = await render(target, parseDocument(doc({ tag: "Widget", name: "table", props: deferred })),
    defaultRegistry(), env(document));
  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0]?.message ?? "", /deferred relation could not be resolved/);
});

test("(d-fetch) httpFetchData builds GET <base>/data/<token> and validates the answer", async () => {
  const urls: string[] = [];
  const ok = httpFetchData("/report/", async (url) => {
    urls.push(url);
    return { ok: true, status: 200, json: async () => rel };
  });
  assert.deepStrictEqual(await ok("a/b"), rel);
  assert.deepStrictEqual(urls, ["/report/data/a%2Fb"]);
  const notInline = httpFetchData("/report", async () => ({ ok: true, status: 200, json: async () => ({ kind: "deferred" }) }));
  await assert.rejects(() => notInline("t"), /did not answer an inline relation/);
  const missing = httpFetchData("/report", async () => ({ ok: false, status: 404, json: async () => ({}) }));
  await assert.rejects(() => missing("t"), /404/);
});

test("(d-resolve) resolveRelations walks arbitrarily nested props", async () => {
  const deferred = { kind: "deferred", columns: rel.columns, token: "t", expires: "2099-01-01T00:00:00.000Z" };
  const nested = { a: [{ b: deferred }], c: { d: [deferred, 1, "x", null] } };
  const out = await resolveRelations(nested, async () => rel);
  assert.deepStrictEqual(out, { a: [{ b: rel }], c: { d: [rel, 1, "x", null] } });
});

test("(d-empty) an empty relation renders an empty table and an empty scorecard", async () => {
  const { document, target } = newDom();
  const empty = inlineRelation([{ name: "region", type: "String" }, { name: "sales", type: "Double" }], []);
  const hw = stubHtmlWriter();
  const root = {
    tag: "VFlow",
    children: [
      { tag: "Widget", name: "table", props: { ...tableProps, rows: empty } },
      { tag: "Widget", name: "scorecard", props: { ...scorecardProps, cards: empty } },
    ],
  };
  const result = await render(target, parseDocument(doc(root)), defaultRegistry(), { document, fetchData: refusingFetch, htmlwriter: hw });
  assert.deepStrictEqual(result.errors, []);
  assert.deepStrictEqual(hw.calls[0]?.relation, []);
  assert.equal(target.querySelectorAll(".ermine-scorecard-card").length, 0);
  assert.ok(target.querySelector(".ermine-scorecard-empty"));
});

test("(d-mutation) every single mutation of a valid document is refused, and an error box takes its place", async () => {
  const root = {
    tag: "VFlow",
    children: [
      { tag: "Widget", name: "table", props: tableProps },
      { tag: "Widget", name: "scorecard", props: scorecardProps },
    ],
  };
  const valid = doc(root);
  let mutated = 0;
  const kinds = new Set<string>();
  let seed = 1;
  const rand = (): number => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648;
  };
  for (let i = 0; i < 400; i++) {
    const m = mutateOnce(valid, rand);
    if (!m) continue;
    if (JSON.stringify(m.after) === JSON.stringify(valid)) continue;
    const parsed = safeParseDocument(m.after);
    if (!parsed.ok) {
      // the envelope schema caught it: it must say what, and where
      assert.ok(parsed.error.issues.length > 0);
      assert.ok(Array.isArray(parsed.error.issues[0]?.path));
      mutated++;
      kinds.add(m.how);
      continue;
    }
    // the envelope accepted it (props are `unknown` there), so the WIDGET schema
    // must refuse it and the dispatcher must show the box
    const { document, target } = newDom();
    const result = await render(target, parsed.document, defaultRegistry(), env(document));
    assert.ok(result.errors.length > 0,
      `mutation ${m.how} at ${m.path.join(".")} was accepted: ${JSON.stringify(m.after).slice(0, 300)}`);
    assert.ok(target.querySelector(".ermine-widget-error"));
    mutated++;
    kinds.add(m.how);
  }
  assert.ok(mutated > 300, `only ${mutated} mutations were produced`);
  assert.deepStrictEqual([...kinds].sort(), ["add", "drop", "retype"]);
});

test("(d-errorbox) the error box carries the widget name and the detail", () => {
  const { document } = newDom();
  const box = errorBox(document, "treeMap", "not supported yet");
  assert.equal(box.getAttribute("data-widget"), "treeMap");
  assert.equal(box.getAttribute("role"), "alert");
  assert.match(box.textContent ?? "", /treeMap/);
  assert.match(box.textContent ?? "", /not supported yet/);
});
