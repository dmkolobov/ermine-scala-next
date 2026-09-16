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
export { scorecardWidget, deltaDirection } from "./widgets/scorecard";
export { WIDGET_PROP_SCHEMAS } from "./generated";

import type { Registry } from "./dispatcher";
import type { FormatEnv } from "./format";
import { drilldownTableWidget, tableWidget } from "./legacy";
import { scorecardWidget } from "./widgets/scorecard";

/** Every widget this stage ships.  The chart names Layout.Widgets reserves --
 *  axisChart, pieChart, drilldownPieChart, styleBox, drilldownBar, treeMap -- are
 *  J3e's; until then the dispatcher renders an error box naming them, which is the
 *  intended behaviour for a report that asks for one. */
export function defaultRegistry(env?: FormatEnv): Registry {
  return {
    table: tableWidget(env) as Registry[string],
    drilldownTable: drilldownTableWidget(env) as Registry[string],
    scorecard: scorecardWidget(env) as Registry[string],
  };
}
