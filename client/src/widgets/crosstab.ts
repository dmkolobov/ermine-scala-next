// The widget a query cannot produce (stage J3i).  A relation's row type is
// fixed at compile time, so a table whose COLUMNS are the distinct values of
// a data column has to be built from rows that were read while the report
// was being built -- `Layout.Widgets.Crosstab.crosstabOf` is a `Fetch Node`
// that scans, sums per (row key, column key) pair, and sends a MATRIX.  So
// this component does not go through the table adapter: what arrives is two
// label lists and `cells`, not a relation.
//
//   <section class="ermine-crosstab">
//     <h3 class="ermine-crosstab-title">Sales by region and month</h3>
//     <table class="ermine-crosstab-table">
//       <thead>
//         <tr><th class="ermine-crosstab-corner">
//               <span class="ermine-crosstab-row-header">Region</span>
//               <span class="ermine-crosstab-col-header">Month</span></th>
//             <th scope="col">2026-01</th> ... <th class="ermine-crosstab-head-total">Total</th></tr>
//       </thead>
//       <tbody>
//         <tr><th scope="row">east</th>
//             <td class="ermine-crosstab-empty">—</td>
//             <td>$75.50</td> ... <td class="ermine-crosstab-row-total">$4,175.50</td></tr>
//       </tbody>
//       <tfoot>
//         <tr><th scope="row">Total</th><td>...</td>
//             <td class="ermine-crosstab-grand-total">$12,682.00</td></tr>
//       </tfoot>
//     </table>
//   </section>
//
// Every number goes through `crosstabFormat` with src/format.ts, the way a
// table cell does.  A `null` cell is a pair NO ROW HAD -- which is not a
// zero -- and it shows as an em dash, the same one `scorecard.ts` uses for a
// missing column.

import type { CrosstabProps } from "../generated/widgets";
import { defaultFormatEnv, formatDisplay, type FormatEnv, type Formatted } from "../format";
import type { Widget, WidgetContext } from "../dispatcher";

/** A pair no row had, and a total the document did not send. */
export const EMPTY_CELL = "—"; // em dash

/** The `<th>` of the totals row and column. */
export const TOTAL_LABEL = "Total";

function text(v: Formatted): string {
  if (v === null || v === undefined) return EMPTY_CELL;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  return String(v);
}

export function crosstabWidget(env?: FormatEnv): Widget<CrosstabProps> {
  return {
    render(ctx: WidgetContext, props: CrosstabProps): void {
      const d = ctx.document;
      const fenv = env ?? defaultFormatEnv(d);
      const format = formatDisplay(props.crosstabFormat, fenv);
      /** A number through the props' format; anything absent is the em dash. */
      const cell = (v: number | null | undefined): string =>
        v === null || v === undefined ? EMPTY_CELL : text(format([v]));

      const section = d.createElement("section");
      section.className = "ermine-crosstab";
      section.id = ctx.uid();

      const title = d.createElement("h3");
      title.className = "ermine-crosstab-title";
      title.textContent = props.crosstabTitle;
      section.appendChild(title);

      const table = d.createElement("table");
      table.className = "ermine-crosstab-table";

      // the header row: what the keys are in the corner, then the column labels
      const thead = d.createElement("thead");
      const headRow = d.createElement("tr");
      const corner = d.createElement("th");
      corner.className = "ermine-crosstab-corner";
      corner.setAttribute("scope", "col");
      const rowHead = d.createElement("span");
      rowHead.className = "ermine-crosstab-row-header";
      rowHead.textContent = props.rowHeader;
      const colHead = d.createElement("span");
      colHead.className = "ermine-crosstab-col-header";
      colHead.textContent = props.colHeader;
      corner.appendChild(rowHead);
      corner.appendChild(colHead);
      headRow.appendChild(corner);
      for (const label of props.crosstabColLabels) {
        const th = d.createElement("th");
        th.setAttribute("scope", "col");
        th.textContent = label;
        headRow.appendChild(th);
      }
      const headTotal = d.createElement("th");
      headTotal.className = "ermine-crosstab-head-total";
      headTotal.setAttribute("scope", "col");
      headTotal.textContent = TOTAL_LABEL;
      headRow.appendChild(headTotal);
      thead.appendChild(headRow);
      table.appendChild(thead);

      // one body row per row label: the label, the cells, the row total
      const tbody = d.createElement("tbody");
      props.crosstabRowLabels.forEach((label, i) => {
        const tr = d.createElement("tr");
        const th = d.createElement("th");
        th.setAttribute("scope", "row");
        th.textContent = label;
        tr.appendChild(th);
        const row = props.cells[i] ?? [];
        props.crosstabColLabels.forEach((_, j) => {
          const td = d.createElement("td");
          const v = row[j] ?? null;
          if (v === null) td.className = "ermine-crosstab-empty";
          td.textContent = cell(v);
          tr.appendChild(td);
        });
        const total = d.createElement("td");
        total.className = "ermine-crosstab-row-total";
        total.textContent = cell(props.rowTotals[i]);
        tr.appendChild(total);
        tbody.appendChild(tr);
      });
      table.appendChild(tbody);

      // the totals row
      const tfoot = d.createElement("tfoot");
      const footRow = d.createElement("tr");
      const footHead = d.createElement("th");
      footHead.setAttribute("scope", "row");
      footHead.textContent = TOTAL_LABEL;
      footRow.appendChild(footHead);
      props.crosstabColLabels.forEach((_, j) => {
        const td = d.createElement("td");
        td.textContent = cell(props.colTotals[j]);
        footRow.appendChild(td);
      });
      const grand = d.createElement("td");
      grand.className = "ermine-crosstab-grand-total";
      grand.textContent = cell(props.grandTotal);
      footRow.appendChild(grand);
      tfoot.appendChild(footRow);
      table.appendChild(tfoot);

      section.appendChild(table);

      // an empty scan has no axes at all: say so rather than draw a 1x1 grid
      if (props.crosstabRowLabels.length === 0 || props.crosstabColLabels.length === 0) {
        const empty = d.createElement("p");
        empty.className = "ermine-crosstab-no-rows";
        empty.textContent = "no rows";
        section.appendChild(empty);
      }

      ctx.target.appendChild(section);
    },
  };
}
