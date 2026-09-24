#!/usr/bin/env node
// The CI equality check of design note section 3.5 (WP-33: the node port of
// check-generated.sh): regenerate the zod into a temp file (one JVM, generate.js)
// and compare it byte-for-byte with the committed src/generated/widgets.ts.  Exits
// 0 when they are identical, 1 otherwise (stdout: the first differing line of each;
// the bash version printed `diff -u`, which Windows does not have), or the
// generator's own exit code when regeneration fails.  scripts/check-fresh.js is the
// JVM-free half (hashes + exactness probe) that the `generated` and `client` gates run.
//
//   node client/scripts/check-generated.js        (npm run check-generated)
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const gen = require("./generate.js");

// The first line where a and b (Buffers) differ, as text, or null when identical.
function firstDifference(a, b) {
  if (Buffer.compare(a, b) === 0) return null;
  const al = a.toString("utf8").split("\n");
  const bl = b.toString("utf8").split("\n");
  for (let i = 0; ; i++) {
    if (al[i] !== bl[i]) {
      const show = (s) => (s === undefined ? "(end of file)" : JSON.stringify(s));
      return `first difference at line ${i + 1}:\n- ${show(al[i])}\n+ ${show(bl[i])}`;
    }
  }
}

function main() {
  const client = path.resolve(__dirname, "..");
  const repo = path.dirname(client);
  const committed = path.join(client, "src", "generated", "widgets.ts");
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "check-generated-"));
  try {
    const fresh = path.join(tmp, "widgets.ts");
    try {
      gen.generate(repo, fresh);
    } catch (e) {
      if (!(e instanceof gen.GenError)) throw e;
      process.stderr.write(e.message + "\n");
      return e.rc;
    }
    const a = fs.existsSync(committed) ? fs.readFileSync(committed) : Buffer.alloc(0);
    const diff = firstDifference(a, fs.readFileSync(fresh));
    if (diff === null) {
      console.log("check-generated: src/generated/widgets.ts is up to date");
      return 0;
    }
    console.log(diff);
    console.error("check-generated: src/generated/widgets.ts is STALE -- run client/scripts/generate.sh");
    return 1;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

module.exports = { firstDifference };
if (require.main === module) process.exitCode = main();
