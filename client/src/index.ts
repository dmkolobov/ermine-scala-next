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

export * from "./props";
export * from "./relation";
export * from "./format";
export * from "./document";
export * from "./dispatcher";
export * from "./legacy";
export * from "./charts";
export { scorecardWidget, deltaDirection } from "./widgets/scorecard";
export { headlineWidget, HEADLINE_FIGURES } from "./widgets/headline";
export { crosstabWidget, EMPTY_CELL, TOTAL_LABEL } from "./widgets/crosstab";
export { headingWidget, HeadingPropsSchema } from "./widgets/heading";
export { textWidget, TextPropsSchema } from "./widgets/text";
export { WIDGET_PROP_SCHEMAS, UNSUPPORTED_WIDGETS } from "./generated";

import type { Registry } from "./dispatcher";
import type { FormatEnv } from "./format";
import { drilldownTableWidget, tableWidget } from "./legacy";
import { axisChartWidget, drilldownBarWidget, pieChartWidget, styleBoxWidget } from "./charts";
import { scorecardWidget } from "./widgets/scorecard";
import { headlineWidget } from "./widgets/headline";
import { crosstabWidget } from "./widgets/crosstab";
import { headingWidget } from "./widgets/heading";
import { textWidget } from "./widgets/text";

/** Every widget Stage 3 ships.
 *
 *  `treeMap` is NOT here on purpose.  It is the one reserved name with no
 *  renderer behind it at all -- `runTreeMap` is undefined in the ermine-writers
 *  bundle and the Local branch of `HTMLWriter.treeMap` is `sys.error("todo")` --
 *  so leaving it unregistered makes the dispatcher draw its error box naming the
 *  widget, which IS the "unsupported widget" behaviour.  `UNSUPPORTED_WIDGETS`
 *  names it; `test/charts.test.ts` `(x-treemap)` pins the box.
 *
 *  `heading` and `text` (Q24 (d), 2026-09-23) are the two names `Sales.e` uses
 *  that are NOT typed `Layout.Widgets.*` modules: they have no generated zod,
 *  so each carries its own schema (`Widget.schema`) and is absent from the
 *  generated `WIDGET_PROP_SCHEMAS`.  `(w-own-schema)` pins that every
 *  registered name has exactly one of the two. */
export function defaultRegistry(env?: FormatEnv): Registry {
  return {
    table: tableWidget(env) as Registry[string],
    drilldownTable: drilldownTableWidget(env) as Registry[string],
    scorecard: scorecardWidget(env) as Registry[string],
    headline: headlineWidget(env) as Registry[string],
    crosstab: crosstabWidget(env) as Registry[string],
    axisChart: axisChartWidget() as Registry[string],
    pieChart: pieChartWidget(false, env) as Registry[string],
    drilldownPieChart: pieChartWidget(true, env) as Registry[string],
    styleBox: styleBoxWidget(env) as Registry[string],
    drilldownBar: drilldownBarWidget() as Registry[string],
    heading: headingWidget() as Registry[string],
    text: textWidget() as Registry[string],
  };
}
