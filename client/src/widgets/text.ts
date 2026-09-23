// `text`: a paragraph.  `core/src/test/resources/doc/Sales.e` asks for
//
//   rawWidget "text" "line items on demand"
//
// and `widget n p` applies `toJson` to `p`, so the props ON THE WIRE are a bare
// JSON string -- MEASURED from the S1 capture (`scratch-widget-preview/wp10-s1/
// captures.json`, `ok-sales`: `"props": "line items on demand"`), not a
// `{text}` record.  Like `heading` it is outside the typed `Layout.Widgets.*`
// vocabulary, so it carries its own schema through `Widget.schema`.  Added by
// Q24 (d), 2026-09-23.  The DOM, built with textContent only:
//
//   <p class="ermine-text">line items on demand</p>

import { z } from "zod";
import type { Widget, WidgetContext } from "../dispatcher";

export const TextPropsSchema = z.string();

export function textWidget(): Widget<string> {
  return {
    schema: TextPropsSchema,
    render(ctx: WidgetContext, props: string): void {
      const p = ctx.document.createElement("p");
      p.className = "ermine-text";
      p.textContent = props;
      ctx.target.appendChild(p);
    },
  };
}
