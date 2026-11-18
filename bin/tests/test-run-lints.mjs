#!/usr/bin/env node
// bin/run-lints.mjs のユニットテスト。--step で疑似 lint を差し込んで検証する。

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RUNNER = path.resolve(HERE, "..", "run-lints.mjs");

let pass = 0;
let fail = 0;
function test(name, fn) {
  try {
    fn();
    pass++;
    console.log(`  PASS: ${name}`);
  } catch (e) {
    fail++;
    console.log(`  FAIL: ${name}\n    ${e.message}`);
  }
}
const run = (args, env = {}) =>
  spawnSync("node", [RUNNER, ...args], { encoding: "utf8", env: { ...process.env, ...env } });

test("全件成功なら exit 0 で定義順に出力する", () => {
  const r = run(["--step", "sleep 0.3; echo slow", "--step", "echo fast"]);
  assert.equal(r.status, 0);
  assert.ok(r.stdout.indexOf("slow") < r.stdout.indexOf("fast"), r.stdout);
});

test("1 件でも失敗すれば exit 1 で失敗した lint を列挙する", () => {
  const r = run(["--step", "echo ok", "--step", "echo boom >&2; exit 3"]);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /boom/);
  assert.match(r.stderr, /FAIL: echo boom/);
});

test("失敗後も残りの lint を実行する", () => {
  const r = run(["--step", "exit 1", "--step", "echo after"], { JOBS: "1" });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /after/);
});

test("--jobs 1 で逐次、2 で並列に実行される", () => {
  const steps = ["--step", "sleep 0.5", "--step", "sleep 0.5"];
  let t = Date.now();
  run(["--jobs", "1", ...steps]);
  const serial = Date.now() - t;
  t = Date.now();
  run(["--jobs", "2", ...steps]);
  const parallel = Date.now() - t;
  assert.ok(parallel < serial - 300, `serial=${serial} parallel=${parallel}`);
});

test("多バイト文字がチャンク境界をまたいでも文字化けしない", () => {
  const r = run([
    "--step",
    "printf '\\346\\247'; sleep 0.3; printf '\\213\\346\\226\\207\\n'",
  ]);
  assert.equal(r.status, 0);
  assert.match(r.stdout, /構文/);
});

test("不正な JOBS は exit 2", () => {
  assert.equal(run(["--step", "true"], { JOBS: "0" }).status, 2);
});

test("不明な引数は exit 2", () => {
  assert.equal(run(["--bogus"]).status, 2);
});

console.log(`\npassed: ${pass}, failed: ${fail}`);
process.exit(fail === 0 ? 0 : 1);
