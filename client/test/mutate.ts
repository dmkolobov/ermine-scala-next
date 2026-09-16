// One structural mutation of a document, for property (d).  The same three moves
// the Scala side uses (TestWidgets.mutate): drop a key, retype a leaf, add a key.
// A field whose Ermine type is `Maybe a` is an OPTIONAL key, so dropping it is not
// a mutation any schema can refuse -- those are retyped or added to instead.

export const OPTIONAL_KEYS = new Set(["rowGroup", "cardDelta"]);

export interface Mutation {
  path: string[];
  how: "drop" | "retype" | "add";
  before: unknown;
  after: unknown;
}

function objectPaths(value: unknown, path: string[], out: string[][]): void {
  if (Array.isArray(value)) {
    value.forEach((v, i) => objectPaths(v, [...path, String(i)], out));
  } else if (value !== null && typeof value === "object") {
    for (const k of Object.keys(value as Record<string, unknown>)) {
      out.push([...path, k]);
      objectPaths((value as Record<string, unknown>)[k], [...path, k], out);
    }
  }
}

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

function at(v: unknown, path: string[]): unknown {
  let cur = v;
  for (const k of path) cur = (cur as Record<string, unknown>)[k];
  return cur;
}

/** `null` when the value holds no object key to mutate. */
export function mutateOnce(doc: unknown, rand: () => number): Mutation | null {
  const sites: string[][] = [];
  objectPaths(doc, [], sites);
  // never mutate the envelope's own keys: the test wants a PROPS-level mutant
  const usable = sites.filter((p) => p.length > 1);
  if (usable.length === 0) return null;
  const path = usable[Math.floor(rand() * usable.length)] as string[];
  const key = path[path.length - 1] as string;
  const how: Mutation["how"] = OPTIONAL_KEYS.has(key)
    ? (rand() < 0.5 ? "retype" : "add")
    : (["drop", "retype", "add"] as const)[Math.floor(rand() * 3)] as Mutation["how"];

  const after = clone(doc);
  const parent = at(after, path.slice(0, -1)) as Record<string, unknown>;
  const before = parent[key];
  switch (how) {
    case "drop":
      delete parent[key];
      break;
    case "retype":
      parent[key] = typeof before === "string" ? 12345 : "mutant";
      break;
    case "add":
      parent[`${key}X`] = "extra";
      break;
  }
  return { path, how, before, after };
}
