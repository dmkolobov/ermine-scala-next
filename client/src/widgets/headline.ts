// The widget whose ERMINE constructor scans (stage J3g).  `Layout.Widgets.
// Headline.headlineOf` is a `Fetch Node`: it reads the relation itself and
// puts the three numbers in the props, so nothing about the rows reaches the
// client and this component is as plain as the scorecard's.
//
//   <section class="ermine-headline">
//     <h3 class="ermine-headline-title">Sales</h3>   <!-- headlineTitle -->
//     <p class="ermine-headline-scope">in north</p>
//     <dl class="ermine-headline-figures">
//       <div class="ermine-headline-figure" data-figure="rowCount">
//         <dt>Rows</dt><dd>3</dd></div>
//       <div class="ermine-headline-figure" data-figure="total">
//         <dt>Total</dt><dd>$4,350.75</dd></div>
//       <div class="ermine-headline-figure" data-figure="largest">
//         <dt>Largest</dt><dd>$2,310.25</dd></div>
//     </dl>
//   </section>
//
// `total` and `largest` go through `headlineFormat` with src/format.ts, the
// way a table cell does; `rowCount` is a count, not a measurement, so it is
// printed as it arrives.

import type { HeadlineProps } from "../props";
import { defaultFormatEnv, formatDisplay, type FormatEnv, type Formatted } from "../format";
import type { Widget, WidgetContext } from "../dispatcher";

/** The numeric props, in the order they are laid out. */
export type HeadlineFigure = "rowCount" | "total" | "largest";

/** The `<dt>` of each figure, in the order they are laid out. */
export const HEADLINE_FIGURES: readonly [HeadlineFigure, string][] = [
  ["rowCount", "Rows"],
  ["total", "Total"],
  ["largest", "Largest"],
];

function text(v: Formatted): string {
  if (v === null || v === undefined) return "";
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  return String(v);
}

export function headlineWidget(env?: FormatEnv): Widget<HeadlineProps> {
  return {
    render(ctx: WidgetContext, props: HeadlineProps): void {
      const d = ctx.document;
      const fenv = env ?? defaultFormatEnv(d);
      const format = formatDisplay(props.headlineFormat, fenv);

      const section = d.createElement("section");
      section.className = "ermine-headline";
      section.id = ctx.uid();

      const title = d.createElement("h3");
      title.className = "ermine-headline-title";
      title.textContent = props.headlineTitle;
      section.appendChild(title);

      const scope = d.createElement("p");
      scope.className = "ermine-headline-scope";
      scope.textContent = props.scope;
      section.appendChild(scope);

      const figures = d.createElement("dl");
      figures.className = "ermine-headline-figures";
      for (const [key, label] of HEADLINE_FIGURES) {
        const box = d.createElement("div");
        box.className = "ermine-headline-figure";
        box.setAttribute("data-figure", key);

        const dt = d.createElement("dt");
        dt.textContent = label;
        box.appendChild(dt);

        const dd = d.createElement("dd");
        // the count is a count; the two measurements take the props' format
        dd.textContent = key === "rowCount" ? String(props.rowCount) : text(format([props[key]]));
        box.appendChild(dd);

        figures.appendChild(box);
      }
      section.appendChild(figures);

      ctx.target.appendChild(section);
    },
  };
}
