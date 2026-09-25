import { test } from "node:test";
import assert from "node:assert/strict";
import { Pcg32, fnv1a64, stream } from "../src/lib/pcg32.js";

// A literal transcription of pcg_basic.c with BigInt, the oracle for the
// 32-bit-halves implementation.
class RefPcg {
  state = 0n; inc = 0n;
  static M = (1n << 64n) - 1n;
  constructor(initstate: bigint, initseq: bigint) {
    this.inc = ((initseq << 1n) | 1n) & RefPcg.M;
    this.next(); this.state = (this.state + initstate) & RefPcg.M; this.next();
  }
  next(): number {
    const old = this.state;
    this.state = (old * 6364136223846793005n + this.inc) & RefPcg.M;
    const xs = Number((((old >> 18n) ^ old) >> 27n) & 0xffffffffn);
    const rot = Number(old >> 59n);
    return ((xs >>> rot) | (xs << ((32 - rot) & 31))) >>> 0;
  }
}

test("pcg32: the reference pcg32-demo vector (initstate 42, initseq 54)", () => {
  const g = new Pcg32(42n, 54n);
  const got = Array.from({ length: 6 }, () => g.nextU32());
  assert.deepEqual(got, [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]);
});

test("pcg32: agrees with a BigInt transcription for 10 000 draws on 20 seeds", () => {
  for (let s = 0; s < 20; s++) {
    const seed = BigInt(s) * 0x9e3779b97f4a7c15n & RefPcg.M;
    const seq = fnv1a64(`seq${s}`);
    const a = new Pcg32(seed, seq), b = new RefPcg(seed, seq);
    for (let i = 0; i < 10000; i++) assert.equal(a.nextU32(), b.next());
  }
});

test("pcg32: bounded is in range and roughly uniform; nextFloat in [0,1)", () => {
  const g = stream(7, "t/bounded");
  const counts = new Array(10).fill(0);
  for (let i = 0; i < 100000; i++) counts[g.bounded(10)]++;
  for (const c of counts) assert.ok(Math.abs(c - 10000) < 600, `count ${c}`);
  for (let i = 0; i < 10000; i++) { const f = g.nextFloat(); assert.ok(f >= 0 && f < 1); }
});

test("fnv1a64: the published vectors", () => {
  assert.equal(fnv1a64(""), 0xcbf29ce484222325n);
  assert.equal(fnv1a64("a"), 0xaf63dc4c8601ec8cn);
  assert.equal(fnv1a64("foobar"), 0x85944171f73967e8n);
});
