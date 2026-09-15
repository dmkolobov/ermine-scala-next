// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Test/{..(|sfBool, sfDate, sfInt, sfString|)}
// zod 3

import { z } from "zod";

export const Schema = z.object({ sfBool: z.boolean(), sfDate: z.string().date(), sfInt: z.number().int(), sfString: z.string() }).strict();
export type Schema = z.infer<typeof Schema>;
