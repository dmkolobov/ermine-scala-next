// `heading`: the typed widget `Layout.Widgets.Heading` (core/src/main/resources/
// modules/Layout/Widgets/Heading.e), built in Ermine with
//
//   heading (HeadingProps "Sales" (columnOf (orderBy q)) (length picked) total)
//
// Its props are validated by the zod GENERATED from `HeadingProps`
// (src/generated/heading.ts, through WIDGET_PROP_SCHEMAS) like every other
// widget's -- this component carries no schema of its own.  Q25 (2026-09-23,
// the user: "I'm pretty sure I want typed widget schemas in the typescript
// rather than matching runtime ermine values fallibly"): the client never
// validates a bare runtime value with a hand-written schema.
//
// On the wire, a one-constructor record, so no "tag" key:
//
//   {"title": "Sales", "sortColumn": "amount", "matched": 3, "total": 4350.75}
//
// The DOM, built with textContent only (nothing is parsed as HTML):
//
//   <section class="ermine-heading">
//     <h2 class="ermine-heading-title">Sales</h2>
//     <p class="ermine-heading-summary">
//       <span class="ermine-heading-matched">3 matched</span>,
//       <span class="ermine-heading-total">total 4350.75</span>,
//       <span class="ermine-heading-sort">sorted by amount</span>
//     </p>
//   </section>
//
// `total` has no CellFormat in the record, so it is printed as it arrives.

import type { HeadingProps } from "../generated/widgets";
import type { Widget, WidgetContext } from "../dispatcher";

export function headingWidget(): Widget<HeadingProps> {
  return {
    render(ctx: WidgetContext, props: HeadingProps): void {
      const d = ctx.document;
      const section = d.createElement("section");
      section.className = "ermine-heading";
      section.id = ctx.uid();

      const title = d.createElement("h2");
      title.className = "ermine-heading-title";
      title.textContent = props.title;
      section.appendChild(title);

      const summary = d.createElement("p");
      summary.className = "ermine-heading-summary";
      const part = (cls: string, text: string): HTMLElement => {
        const s = d.createElement("span");
        s.className = cls;
        s.textContent = text;
        return s;
      };
      summary.appendChild(part("ermine-heading-matched", `${props.matched} matched`));
      summary.appendChild(d.createTextNode(", "));
      summary.appendChild(part("ermine-heading-total", `total ${props.total}`));
      summary.appendChild(d.createTextNode(", "));
      summary.appendChild(part("ermine-heading-sort", `sorted by ${props.sortColumn}`));
      section.appendChild(summary);

      ctx.target.appendChild(section);
    },
  };
}
