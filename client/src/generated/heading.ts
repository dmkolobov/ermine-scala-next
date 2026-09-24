// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Layout.Widgets.Heading/HeadingProps
// zod 3

import { z } from "zod";

export const Layout_Widgets_Heading_HeadingProps = z.object({ title: z.string(), sortColumn: z.string(), matched: z.number().int(), total: z.number() }).strict();
export type Layout_Widgets_Heading_HeadingProps = z.infer<typeof Layout_Widgets_Heading_HeadingProps>;

export const Schema = Layout_Widgets_Heading_HeadingProps;
export type Schema = z.infer<typeof Schema>;
