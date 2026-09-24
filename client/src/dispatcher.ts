// The dispatcher (design note section 3.2): walk a Layout.Doc.Node, build plain DOM
// for the layout constructors, and for a Widget look the name up in the registry,
// validate its props with the GENERATED zod, resolve any relation inside them, and
// hand the result to the renderer.
//
// Nothing here knows about a particular widget.  Adding one is a `data` type in
// Ermine, an entry in client/scripts/generate.sh, one TypeScript component and one
// registry line -- see client/README.md.
//
// A widget NEVER throws past the dispatcher: an unknown name, a props value the
// schema refuses, a deferred relation that will not resolve and an exception from
// the renderer itself all render an error box naming the widget, the document path
// and (for a validation failure) the zod path.  One broken widget must not take the
// page with it.

import type { ReportDocument } from "./document";
import type { DocNode, DocTab } from "./props";
import { WIDGET_PROP_SCHEMAS } from "./generated";
import { resolveRelations, zodMessage, type FetchData } from "./relation";

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
   *  id).  Defaults to "ermine". */
  idPrefix?: string;
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

/** A renderer.  It carries NO schema: its props are validated by the zod GENERATED
 *  from its `Layout.Widgets.*` module (`WIDGET_PROP_SCHEMAS`) or the widget is an
 *  error box -- never a hand-written check (Q25; client/README.md "Adding a widget"). */
export interface Widget<P = unknown> {
  render(ctx: WidgetContext, props: P): void | Promise<void>;
}

export type Registry = Record<string, Widget<never>>;

export interface RenderError {
  path: string;
  widget: string;
  message: string;
}

export interface RenderResult {
  errors: RenderError[];
}

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
  const prefix = env.idPrefix ?? "ermine";
  const uid = (): string => `${prefix}_${++counter}`;
  target.innerHTML = "";
  const root = await renderNode(doc.root, "$.root", registry, env, errors, uid);
  target.appendChild(root);
  return { errors };
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
      for (const b of Array.from(bar.children)) b.classList.remove("ermine-tab-active");
      button.classList.add("ermine-tab-active");
      for (const p of Array.from(panels.children)) {
        if (p.getAttribute("data-tab") === String(i)) p.removeAttribute("hidden");
        else p.setAttribute("hidden", "hidden");
      }
    });
  }
  return wrapper;
}

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

  const widget = registry[name];
  if (!widget) {
    return fail(`no renderer is registered under that name`);
  }

  const schema = WIDGET_PROP_SCHEMAS[name];
  if (!schema) {
    return fail(`no props schema was generated for it -- add it to client/scripts/generate.sh`);
  }

  const parsed = schema.safeParse(rawProps);
  if (!parsed.success) {
    return fail(`its props are invalid -- ${zodMessage(parsed.error)}`);
  }

  let props: unknown;
  try {
    props = await resolveRelations(parsed.data, env.fetchData);
  } catch (e) {
    return fail(`a deferred relation could not be resolved: ${(e as Error).message}`);
  }

  const host = d.createElement("div");
  host.className = "ermine-widget";
  host.setAttribute("data-widget", name);
  const ctx: WidgetContext = { target: host, env, document: d, path, uid };
  try {
    await widget.render(ctx, props as never);
  } catch (e) {
    host.innerHTML = "";
    const message = `it threw while rendering: ${(e as Error).message}`;
    errors.push({ path, widget: name, message });
    host.appendChild(errorBox(d, name, `${message} (at ${path})`));
  }
  return host;
}
