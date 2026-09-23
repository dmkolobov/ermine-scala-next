// `heading`: the widget `core/src/test/resources/doc/Sales.e` asks for with
//
//   rawWidget "heading" (Heading "Sales" (columnOf (orderBy q)) (length picked) total)
//
// It is NOT one of the typed `Layout.Widgets.*` modules -- `Heading` is a
// report-local `data` type (Sales.e:75-80) -- so there is no generated zod for
// it, and this component carries its OWN schema through `Widget.schema` (the
// dispatcher's documented override) instead of an entry in the generated
// `WIDGET_PROP_SCHEMAS`.  Added by Q24 (d), 2026-09-23, so Sales's heading box
// draws in the preview panel.
//
// The props, MEASURED from the S1 capture (`scratch-widget-preview/wp10-s1/
// captures.json`, `ok-sales`; the same four keys in editor/vscode/test/
// fixtures/panel-answers.json): a one-constructor record, so no "tag" key --
//
//   {"title": "Sales", "sortColumn": "amount", "matched": 3, "total": 4350.75}
//
// and strict, as every generated schema is: an unknown key is refused, not
// ignored.  The DOM, built with textContent only (nothing is parsed as HTML):
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

import { z } from "zod";
import type { Widget, WidgetContext } from "../dispatcher";

export const HeadingPropsSchema = z.object({
  title: z.string(),
  sortColumn: z.string(),
  matched: z.number().int(),
  total: z.number(),
}).strict();

export type HeadingProps = z.infer<typeof HeadingPropsSchema>;

export function headingWidget(): Widget<HeadingProps> {
  return {
    schema: HeadingPropsSchema,
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
