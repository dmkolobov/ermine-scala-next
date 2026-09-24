// The public surface of the Ermine JSON report client.
//
//   const doc = parseDocument(await res.json());
//   await render(target, doc, defaultRegistry(), {
//     document, htmlwriter: window.ermine_htmlwriter,
//     fetchData: httpFetchData("/report", url => fetch(url)),
//   });
//
// THE LEGACY GLOBAL IS `window.ermine_htmlwriter`, and this comment said
// `window.htmlwriter` until WP-9.  Corrected by READING the writers entry
// point, `ermine-writers/writers/js/htmlwriter.js:10-13`:
//
//   document.addEventListener('DOMContentLoaded', () => {
//     window.Object.assign(window, {ermine_htmlwriter, ermine_htmlwriter_conf});
//     window.jQuery = $;
//   });
//
// so the name is one half of it and THE TIMING IS THE OTHER: the assignment
// happens only on `DOMContentLoaded`, and a host page that reads the global at
// script-evaluation time gets `undefined` -- which arrives here as the designed
// "this widget needs the legacy renderers" error box, not as a timing bug.  A
// host page must wait for the event (or poll) before it calls `render`.
// `window.ermine_htmlwriter_conf` IS set at module top level and is therefore a
// RED HERRING for a readiness probe.
//
// Nothing in this package reads a global: `render` takes the writer through
// `env.htmlwriter` and the HOST decides where it came from.  The name above is
// documentation, and what WP-10's host page has to get right.

// The generated vocabulary (WP-32): every props type and schema, WidgetRegistry,
// WidgetName, WIDGET_PROP_SCHEMAS, UNSUPPORTED_WIDGETS, DocNode/DocTab.  Written by
// client/scripts/generate.sh from the Ermine declarations; nothing hand-written.
export * from "./generated/widgets";
export * from "./relation";
export * from "./format";
export * from "./document";
export * from "./dispatcher";
export * from "./legacy";
export * from "./charts";
export { scorecardWidget, deltaDirection } from "./widgets/scorecard";
export { headlineWidget, HEADLINE_FIGURES } from "./widgets/headline";
export { crosstabWidget, EMPTY_CELL, TOTAL_LABEL } from "./widgets/crosstab";
export { headingWidget } from "./widgets/heading";
export { textWidget } from "./widgets/text";

import type { Registry } from "./dispatcher";
import type { FormatEnv } from "./format";
import { drilldownTableWidget, tableWidget } from "./legacy";
import { axisChartWidget, drilldownBarWidget, pieChartWidget, styleBoxWidget } from "./charts";
import { scorecardWidget } from "./widgets/scorecard";
import { headlineWidget } from "./widgets/headline";
import { crosstabWidget } from "./widgets/crosstab";
import { headingWidget } from "./widgets/heading";
import { textWidget } from "./widgets/text";

/** Every widget Stage 3 ships: one renderer per generated widget name.
 *
 *  `treeMap` is NOT here on purpose.  It is the one reserved name with no
 *  renderer behind it at all -- `runTreeMap` is undefined in the ermine-writers
 *  bundle and the Local branch of `HTMLWriter.treeMap` is `sys.error("todo")` --
 *  so leaving it unregistered makes the dispatcher draw its error box naming the
 *  widget, which IS the "unsupported widget" behaviour.  `UNSUPPORTED_WIDGETS`
 *  names it; `test/charts.test.ts` `(x-treemap)` pins the box.
 *
 *  THE INVARIANT (Q25, 2026-09-23; typed by WP-32): the keys are exactly the
 *  generated `WidgetName`s and each renderer is for that name's generated props
 *  type -- `Registry` is `{ [K in WidgetName]: Widget<WidgetRegistry[K]> }`, so a
 *  missing name, an extra name or a renderer for the wrong props type is a tsc
 *  error on this object literal (no casts here, on purpose).  A renderer carries
 *  no schema of its own.  `(w-generated-only)` pins the same at runtime and
 *  `(g-tsc)` pins that tsc refuses the two wrong registrations. */
export function defaultRegistry(env?: FormatEnv): Registry {
  return {
    table: tableWidget(env),
    drilldownTable: drilldownTableWidget(env),
    scorecard: scorecardWidget(env),
    headline: headlineWidget(env),
    crosstab: crosstabWidget(env),
    axisChart: axisChartWidget(),
    pieChart: pieChartWidget(false, env),
    drilldownPieChart: pieChartWidget(true, env),
    styleBox: styleBoxWidget(env),
    drilldownBar: drilldownBarWidget(),
    heading: headingWidget(),
    text: textWidget(),
  };
}
