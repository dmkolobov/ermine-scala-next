// The new widget, end to end: Layout.Widgets.Scorecard.ScorecardProps in Ermine,
// this component in TypeScript, one line in the registry.  No legacy code is
// involved -- it builds its own DOM -- which is the point: it shows what a widget
// costs once the dispatcher, the generated zod and the format port are in place.
//
//   <section class="ermine-scorecard">
//     <h3 class="ermine-scorecard-title">Revenue</h3>
//     <ol class="ermine-scorecard-cards">
//       <li class="ermine-scorecard-card">
//         <span class="ermine-scorecard-label">EMEA</span>
//         <span class="ermine-scorecard-value">$1200</span>
//         <span class="ermine-scorecard-delta ermine-scorecard-delta-up">+3.5</span>
//       </li>
//       ...
//     </ol>
//   </section>
//
// The value is formatted with the props' CellFormat through src/format.ts; the
// delta, when a delta column is named, is formatted the same way and gets an
// up/down/flat class from its sign.  `cards` is an `Inline r` in Ermine, so the
// rows are always in the response and there is no deferred arm to handle.

import type { ScorecardProps } from "../props";
import type { InlineRelation, WireCell } from "../relation";
import { columnIndex } from "../relation";
import { defaultFormatEnv, formatDisplay, type FormatEnv, type Formatted } from "../format";
import type { Widget, WidgetContext } from "../dispatcher";

export const MISSING_COLUMN = "—"; // em dash, when the named column is absent

function text(v: Formatted): string {
  if (v === null || v === undefined) return MISSING_COLUMN;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  return String(v);
}

/** up for a positive delta, down for a negative one, flat for zero or a
 *  non-number (a string delta carries no sign we can read). */
export function deltaDirection(raw: WireCell): "up" | "down" | "flat" {
  if (typeof raw !== "number" || !Number.isFinite(raw) || raw === 0) return "flat";
  return raw > 0 ? "up" : "down";
}

export function scorecardWidget(env?: FormatEnv): Widget<ScorecardProps<InlineRelation>> {
  return {
    render(ctx: WidgetContext, props: ScorecardProps<InlineRelation>): void {
      const d = ctx.document;
      const fenv = env ?? defaultFormatEnv(d);
      const rel = props.cards;
      const labelAt = columnIndex(rel, props.cardLabel);
      const valueAt = columnIndex(rel, props.cardValue);
      const deltaAt = props.cardDelta === undefined ? -1 : columnIndex(rel, props.cardDelta);
      const formatValue = formatDisplay(props.cardFormat, fenv);

      const section = d.createElement("section");
      section.className = "ermine-scorecard";
      section.id = ctx.uid();

      const title = d.createElement("h3");
      title.className = "ermine-scorecard-title";
      title.textContent = props.title;
      section.appendChild(title);

      const list = d.createElement("ol");
      list.className = "ermine-scorecard-cards";
      for (const row of rel.rows) {
        const cell = (at: number): WireCell => (at < 0 ? null : ((row[at] ?? null) as WireCell));
        const card = d.createElement("li");
        card.className = "ermine-scorecard-card";

        const label = d.createElement("span");
        label.className = "ermine-scorecard-label";
        label.textContent = labelAt < 0 ? MISSING_COLUMN : text(cell(labelAt) as Formatted);
        card.appendChild(label);

        const value = d.createElement("span");
        value.className = "ermine-scorecard-value";
        // a null reads as missing rather than through the format, the same rule
        // the table adapter applies (legacy.ts, tabularCell)
        const rawValue = cell(valueAt);
        value.textContent = valueAt < 0 || (rawValue === null && props.cardFormat.tag !== "Constant")
          ? MISSING_COLUMN
          : text(formatValue([rawValue]));
        card.appendChild(value);

        if (deltaAt >= 0) {
          const rawDelta = cell(deltaAt);
          const delta = d.createElement("span");
          const dir = deltaDirection(rawDelta);
          delta.className = `ermine-scorecard-delta ermine-scorecard-delta-${dir}`;
          delta.setAttribute("data-direction", dir);
          delta.textContent = rawDelta === null && props.cardFormat.tag !== "Constant"
            ? MISSING_COLUMN
            : text(formatValue([rawDelta]));
          card.appendChild(delta);
        }
        list.appendChild(card);
      }
      section.appendChild(list);

      if (rel.rows.length === 0) {
        const empty = d.createElement("p");
        empty.className = "ermine-scorecard-empty";
        empty.textContent = "no rows";
        section.appendChild(empty);
      }

      ctx.target.appendChild(section);
    },
  };
}
