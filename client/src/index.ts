// The public surface of the Ermine JSON report client.
//
//   const doc = parseDocument(await res.json());
//   await render(target, doc, defaultRegistry(), {
//     document, htmlwriter: window.htmlwriter,
//     fetchData: httpFetchData("/report", url => fetch(url)),
//   });

export * from "./props";
export * from "./relation";
export * from "./format";
export * from "./document";
export * from "./dispatcher";
export * from "./legacy";
export * from "./charts";
export { scorecardWidget, deltaDirection } from "./widgets/scorecard";
export { WIDGET_PROP_SCHEMAS, UNSUPPORTED_WIDGETS } from "./generated";

import type { Registry } from "./dispatcher";
import type { FormatEnv } from "./format";
import { drilldownTableWidget, tableWidget } from "./legacy";
import { axisChartWidget, drilldownBarWidget, pieChartWidget, styleBoxWidget } from "./charts";
import { scorecardWidget } from "./widgets/scorecard";

/** Every widget Stage 3 ships.
 *
 *  `treeMap` is NOT here on purpose.  It is the one reserved name with no
 *  renderer behind it at all -- `runTreeMap` is undefined in the ermine-writers
 *  bundle and the Local branch of `HTMLWriter.treeMap` is `sys.error("todo")` --
 *  so leaving it unregistered makes the dispatcher draw its error box naming the
 *  widget, which IS the "unsupported widget" behaviour.  `UNSUPPORTED_WIDGETS`
 *  names it; `test/charts.test.ts` `(x-treemap)` pins the box. */
export function defaultRegistry(env?: FormatEnv): Registry {
  return {
    table: tableWidget(env) as Registry[string],
    drilldownTable: drilldownTableWidget(env) as Registry[string],
    scorecard: scorecardWidget(env) as Registry[string],
    axisChart: axisChartWidget() as Registry[string],
    pieChart: pieChartWidget(false, env) as Registry[string],
    drilldownPieChart: pieChartWidget(true, env) as Registry[string],
    styleBox: styleBoxWidget(env) as Registry[string],
    drilldownBar: drilldownBarWidget() as Registry[string],
  };
}
