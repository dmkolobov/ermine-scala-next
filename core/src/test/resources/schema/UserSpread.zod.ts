// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Test/ChartProps
// zod 3

import { z } from "zod";

export const Test_ChartProps = z.object({ chartTitle: z.string() }).passthrough();
export type Test_ChartProps = z.infer<typeof Test_ChartProps>;

export const Schema = Test_ChartProps;
export type Schema = z.infer<typeof Schema>;
