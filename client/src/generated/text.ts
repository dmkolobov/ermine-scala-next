// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Layout.Widgets.Text/TextProps
// zod 3

import { z } from "zod";

export const Layout_Widgets_Text_TextProps = z.object({ body: z.string() }).strict();
export type Layout_Widgets_Text_TextProps = z.infer<typeof Layout_Widgets_Text_TextProps>;

export const Schema = Layout_Widgets_Text_TextProps;
export type Schema = z.infer<typeof Schema>;
