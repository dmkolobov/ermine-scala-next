// `text`: a paragraph of PLAIN text, the typed widget `Layout.Widgets.Text`
// (core/src/main/resources/modules/Layout/Widgets/Text.e), built in Ermine with
//
//   plainText (TextProps "every line item, whatever the date range")
//
// and validated by the zod GENERATED from `TextProps` (src/generated/text.ts,
// through WIDGET_PROP_SCHEMAS).  On the wire the props are a one-field record,
// `{"body": ".."}` -- never a bare string: since Q25 (2026-09-23) the client's
// widget vocabulary is the typed one and a bare runtime value is refused.
// The DOM, built with textContent only (no HTML, no markdown):
//
//   <p class="ermine-text">every line item, whatever the date range</p>

import type { TextProps } from "../props";
import type { Widget, WidgetContext } from "../dispatcher";

export function textWidget(): Widget<TextProps> {
  return {
    render(ctx: WidgetContext, props: TextProps): void {
      const p = ctx.document.createElement("p");
      p.className = "ermine-text";
      p.textContent = props.body;
      ctx.target.appendChild(p);
    },
  };
}
