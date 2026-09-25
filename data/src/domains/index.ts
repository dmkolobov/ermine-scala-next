import type { Domain } from "../model.js";
import { salesDomain } from "./sales.js";

export const DOMAINS: Record<string, () => Domain> = { sales: salesDomain };
