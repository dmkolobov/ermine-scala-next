// The dispatcher (design note section 3.2): walk a Layout.Doc.Node, build plain DOM
// for the layout constructors, and for a Widget look the name up in the registry,
// validate its props with the GENERATED zod, resolve any relation inside them, and
// hand the result to the renderer.
//
// Nothing here knows about a particular widget.  Adding one is a props type and a
// `WidgetName` value in a Layout/Widgets module, `client/scripts/generate.sh`, one
// TypeScript component and one registry line (tsc names it if it is missing) -- see
// client/README.md.
//
// A widget NEVER throws past the dispatcher: an unknown name, a props value the
// schema refuses, a deferred relation that will not resolve and an exception from
// the renderer itself all render an error box naming the widget, the document path
// and (for a validation failure) the zod path.  One broken widget must not take the
// page with it.

import type { z } from "zod";
import type { ReportDocument } from "./document";
import {
  WIDGET_PROP_SCHEMAS, type DocNode, type DocTab, type WidgetName, type WidgetRegistry,
} from "./generated/widgets";
import { resolveRelations, zodMessage, type FetchData, type Resolved } from "./relation";

export interface RenderEnv {
  /** The Document DOM is built in.  Explicit, so the same code runs in jsdom. */
  document: Document;
  /** How a deferred relation's rows are fetched.  Injectable; the default in
   *  `httpFetchData` is `GET <base>/data/<token>`. */
  fetchData: FetchData;
  /** Everything an adapter onto the legacy renderers needs; absent when only
   *  native widgets are registered. */
  htmlwriter?: unknown;
  /** Prefix for the DOM ids widgets mint (the legacy renderers address tables by
   *  id).  MUST differ from every earlier render's on the same page (WP-36 MF-1:
   *  the writers keep each table's build callback in a page-global list and look
   *  its element up by id, so a reused id lets an OLD render's callback draw its
   *  rows into a NEW table).  Defaults to `ermine_r<N>`, N counting renders in
   *  this module, so the default is unique per page. */
  idPrefix?: string;
  /** WP-36.  Called when a container un-hides content it rendered hidden (today:
   *  a `tabbed` tab switch), with the element now showing.  Absent, the default
   *  is `contentShown`'s: run the legacy writers' resize pass.  A host overrides
   *  it only to observe or replace that pass. */
  onShown?: (shown: Element) => void;
}

/** WP-36.  The ONE "content shown" hook: every container that renders content
 *  hidden and later shows it calls this after un-hiding.  Why it exists: the
 *  legacy table builds its DataTable ONLY while its element is visible
 *  (ermine-writers tables.js:1375-1376 `if (isVisible(...))`), registering the
 *  build as a resize callback (tables.js:1598); a table drawn inside a hidden
 *  tab keeps its placeholder row until something runs those callbacks.  The
 *  writers' `runResize` (ermine-htmlwriter.js:2888, exported :3568) runs them.
 *  A table already built takes the callback's `isInit` branch (tables.js:1377),
 *  which only resizes, so calling this on every switch rebuilds nothing twice
 *  WITHIN one render.  Across renders the ids differ (`idPrefix`), so an older
 *  render's callback finds no element and draws nothing, and the preview host
 *  also retires the older render's callbacks (`invalidateRegion`, WP-36 MF-1).
 *  Without a `runResize` export the fallback is a window `resize` event, which
 *  the writers debounce 100 ms into the same `runResize` (ermine-htmlwriter.js:3521). */
export function contentShown(env: RenderEnv, shown: Element): void {
  if (env.onShown) {
    env.onShown(shown);
    return;
  }
  const hw = env.htmlwriter as { runResize?: unknown } | undefined;
  if (hw && typeof hw.runResize === "function") {
    (hw.runResize as () => void)();
    return;
  }
  const win = env.document.defaultView;
  if (win) win.dispatchEvent(new win.Event("resize"));
}

export interface WidgetContext {
  /** The element the widget owns; it is already in the tree and empty. */
  target: Element;
  env: RenderEnv;
  document: Document;
  /** The walker path of this node, e.g. `$.root.children[1]` -- the same spelling
   *  the Scala writer uses in an encode error. */
  path: string;
  /** A fresh id, unique within this render. */
  uid(): string;
}

/** A renderer for props type `P` (a `WidgetRegistry` entry).  It carries NO schema:
 *  its props are validated by the zod GENERATED from its `Layout.Widgets.*` module
 *  (`WIDGET_PROP_SCHEMAS`) or the widget is an error box -- never a hand-written
 *  check (Q25; client/README.md "Adding a widget").  It is handed the props with
 *  every relation resolved (`Resolved<P>`: inline, never deferred).
 *
 *  `render` is a PROPERTY of function type, not a method: under `strict` a
 *  property's parameter is checked contravariantly, while a method's is bivariant
 *  -- and bivariance would let a renderer for one props type sit under another
 *  widget's name in `Registry`.  It may return void (every renderer but none today
 *  is synchronous); the dispatcher awaits it either way. */
export interface Widget<P> {
  render: (ctx: WidgetContext, props: Resolved<P>) => void | Promise<void>;
}

/** The renderer registry: exactly one renderer per generated widget name, each
 *  for that name's generated props type (WP-32).  A missing name, an extra name
 *  or a renderer for the wrong props type is a tsc error at `defaultRegistry`. */
export type Registry = { [K in WidgetName]: Widget<WidgetRegistry[K]> };

export interface RenderError {
  path: string;
  widget: string;
  message: string;
}

export interface RenderResult {
  errors: RenderError[];
  /** The id prefix this render minted under (WP-36 MF-1): a host retires it
   *  with the writers' `invalidateRegion` when the render is replaced. */
  idPrefix: string;
}

/** Renders so far in this module, for the default id prefix (WP-36 MF-1). */
let renderSeq = 0;

const ERROR_CLASS = "ermine-widget-error";

export function errorBox(doc: Document, widget: string, message: string): HTMLElement {
  const box = doc.createElement("div");
  box.className = ERROR_CLASS;
  box.setAttribute("data-widget", widget);
  box.setAttribute("role", "alert");
  const title = doc.createElement("strong");
  title.textContent = `widget "${widget}" could not be rendered`;
  const detail = doc.createElement("span");
  detail.className = "ermine-widget-error-detail";
  detail.textContent = message;
  box.appendChild(title);
  box.appendChild(detail);
  return box;
}

/**
 * Render a document into `target`, which is emptied first.
 *
 * Resolves when every widget has rendered.  Widget failures are collected in the
 * result rather than thrown; only a caller error (a target from another Document,
 * say) escapes.
 */
export async function render(
  target: Element,
  doc: ReportDocument,
  registry: Registry,
  env: RenderEnv,
): Promise<RenderResult> {
  const errors: RenderError[] = [];
  let counter = 0;
  const prefix = env.idPrefix ?? `ermine_r${++renderSeq}`;
  const uid = (): string => `${prefix}_${++counter}`;
  target.innerHTML = "";
  const root = await renderNode(doc.root, "$.root", registry, env, errors, uid);
  target.appendChild(root);
  return { errors, idPrefix: prefix };
}

async function renderNode(
  node: DocNode,
  path: string,
  registry: Registry,
  env: RenderEnv,
  errors: RenderError[],
  uid: () => string,
): Promise<Element> {
  const d = env.document;
  switch (node.tag) {
    case "VFlow":
    case "HFlow": {
      const el = d.createElement("div");
      el.className = node.tag === "VFlow" ? "ermine-vflow" : "ermine-hflow";
      for (let i = 0; i < node.children.length; i++) {
        const child = node.children[i] as DocNode;
        el.appendChild(await renderNode(child, `${path}.children[${i}]`, registry, env, errors, uid));
      }
      return el;
    }
    case "Grid": {
      const table = d.createElement("div");
      table.className = "ermine-grid";
      for (let r = 0; r < node.cells.length; r++) {
        const rowNodes = node.cells[r] as DocNode[];
        const row = d.createElement("div");
        row.className = "ermine-grid-row";
        for (let c = 0; c < rowNodes.length; c++) {
          const cellNode = rowNodes[c] as DocNode;
          const cell = d.createElement("div");
          cell.className = "ermine-grid-cell";
          cell.appendChild(
            await renderNode(cellNode, `${path}.cells[${r}][${c}]`, registry, env, errors, uid),
          );
          row.appendChild(cell);
        }
        table.appendChild(row);
      }
      return table;
    }
    case "Tabbed":
      return renderTabbed(node.tabs, path, registry, env, errors, uid);
    case "Widget":
      return renderWidget(node.name, node.props, path, registry, env, errors, uid);
  }
}

async function renderTabbed(
  tabs: DocTab[],
  path: string,
  registry: Registry,
  env: RenderEnv,
  errors: RenderError[],
  uid: () => string,
): Promise<Element> {
  const d = env.document;
  const wrapper = d.createElement("div");
  wrapper.className = "ermine-tabbed";
  const bar = d.createElement("div");
  bar.className = "ermine-tab-bar";
  const panels = d.createElement("div");
  panels.className = "ermine-tab-panels";
  wrapper.appendChild(bar);
  wrapper.appendChild(panels);

  for (let i = 0; i < tabs.length; i++) {
    const tab = tabs[i] as DocTab;
    const button = d.createElement("button");
    button.type = "button";
    button.className = "ermine-tab";
    button.textContent = tab.label;
    button.setAttribute("data-tab", String(i));
    if (i === 0) button.classList.add("ermine-tab-active");
    bar.appendChild(button);

    const panel = d.createElement("div");
    panel.className = "ermine-tab-panel";
    panel.setAttribute("data-tab", String(i));
    if (i !== 0) panel.setAttribute("hidden", "hidden");
    panel.appendChild(
      await renderNode(tab.content, `${path}.tabs[${i}].content`, registry, env, errors, uid),
    );
    panels.appendChild(panel);

    button.addEventListener("click", () => {
      const wasHidden = panel.hasAttribute("hidden");
      for (const b of Array.from(bar.children)) b.classList.remove("ermine-tab-active");
      button.classList.add("ermine-tab-active");
      for (const p of Array.from(panels.children)) {
        if (p.getAttribute("data-tab") === String(i)) p.removeAttribute("hidden");
        else p.setAttribute("hidden", "hidden");
      }
      // WP-36: the legacy tables in a tab drawn hidden build only now.
      if (wasHidden) contentShown(env, panel);
    });
  }
  return wrapper;
}

/** The error for a name the registry renders but the generator never found: the
 *  generated `WIDGET_PROP_SCHEMAS` has every `WidgetName` term of Layout.Widgets and
 *  the modules under Layout/Widgets/, so the fix is a declaration there plus a
 *  regeneration.  Reachable only from a registry a JS caller built with an extra
 *  key (a typed `Registry` cannot have one); pinned by `(d-no-schema)`. */
const NO_SCHEMA_MESSAGE =
  "no props schema was generated for it -- declare `xName : WidgetName (XProps r)` " +
  "in a Layout.Widgets module and run client/scripts/generate.sh";

async function renderWidget(
  name: string,
  rawProps: unknown,
  path: string,
  registry: Registry,
  env: RenderEnv,
  errors: RenderError[],
  uid: () => string,
): Promise<Element> {
  const d = env.document;
  const fail = (message: string): Element => {
    errors.push({ path, widget: name, message });
    return errorBox(d, name, `${message} (at ${path})`);
  };

  // A name is a widget exactly when the generator found a `WidgetName` term for
  // it.  Anything else -- a typo, `treeMap` (UNSUPPORTED_WIDGETS) -- is the
  // registry's box; a registry a JS caller built with an extra key is told the
  // schema is missing, as before.  Both lookups are OWN-property checks
  // (`hasOwnProperty`), so `constructor`, `toString` or `__proto__` -- inherited
  // from Object.prototype by every object literal -- are an unknown name, never
  // "no props schema was generated" (S2 review N-3).  There is no list to add a
  // name to: the generator DISCOVERS every `WidgetName` term, so the message says
  // where to declare one (WP-32 S3).
  const own = (o: object, k: string): boolean => Object.prototype.hasOwnProperty.call(o, k);
  if (!own(WIDGET_PROP_SCHEMAS, name)) {
    return own(registry, name)
      ? fail(NO_SCHEMA_MESSAGE)
      : fail(`no renderer is registered under that name`);
  }
  const outcome = await dispatch(name as WidgetName, rawProps, registry, env, errors, path, uid);
  if (typeof outcome === "string") return fail(outcome);
  return outcome;
}

/** The typed half of `renderWidget`, generic in the widget's name so that its
 *  renderer, its schema and its props are the SAME `K`'s: `registry[key]` is a
 *  `Widget<WidgetRegistry[K]>`, the schema a `z.ZodType<WidgetRegistry[K]>`, and
 *  the parsed, resolved props go to `render` with no cast.  Answers the host
 *  element, or the message of the error box to draw instead. */
async function dispatch<K extends WidgetName>(
  key: K,
  rawProps: unknown,
  registry: Registry,
  env: RenderEnv,
  errors: RenderError[],
  path: string,
  uid: () => string,
): Promise<Element | string> {
  const d = env.document;
  const widget: Widget<WidgetRegistry[K]> | undefined = registry[key];
  if (!widget) {
    return `no renderer is registered under that name`;
  }
  const schema: z.ZodType<WidgetRegistry[K]> = WIDGET_PROP_SCHEMAS[key];
  const parsed = schema.safeParse(rawProps);
  if (!parsed.success) {
    return `its props are invalid -- ${zodMessage(parsed.error)}`;
  }

  let props: Resolved<WidgetRegistry[K]>;
  try {
    props = await resolveRelations(parsed.data, env.fetchData);
  } catch (e) {
    return `a deferred relation could not be resolved: ${(e as Error).message}`;
  }

  const host = d.createElement("div");
  host.className = "ermine-widget";
  host.setAttribute("data-widget", key);
  const ctx: WidgetContext = { target: host, env, document: d, path, uid };
  try {
    await widget.render(ctx, props);
  } catch (e) {
    host.innerHTML = "";
    const message = `it threw while rendering: ${(e as Error).message}`;
    errors.push({ path, widget: key, message });
    host.appendChild(errorBox(d, key, `${message} (at ${path})`));
  }
  return host;
}
