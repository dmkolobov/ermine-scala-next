// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Layout.Report.Direction/Direction
// zod 3

import { z } from "zod";

export const Layout_Report_Direction_Direction = z.enum(["Horizontal", "Vertical"]);
export type Layout_Report_Direction_Direction = z.infer<typeof Layout_Report_Direction_Direction>;

export const Schema = Layout_Report_Direction_Direction;
export type Schema = z.infer<typeof Schema>;
