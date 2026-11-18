#!/usr/bin/env node
// make lint の runner。独立した lint を並列に実行し、結果を定義順に出力する。
//
// 使い方: node bin/run-lints.mjs [--jobs <N>] [--step "<shell command>"]...
//   --jobs  同時実行数。既定は JOBS 環境変数、なければ os.availableParallelism()
//   --step  実行するコマンド(sh -c)。指定すると既定の lint 一覧を置き換える(テスト用)
// 各 lint の出力は完了後にまとめて表示し、並列でも行が混ざらない。
// 終了コード: 0 = 全件成功、1 = 失敗あり、2 = 引数不正

import { spawn } from "node:child_process";
import os from "node:os";

const DEFAULT_STEPS = [
  "find bin -name '*.sh' -type f -exec shellcheck {} +",
  "find skills -name '*.sh' -type f -exec shellcheck {} +",
  "sh ./bin/lint-frontmatter.sh",
  "sh ./bin/lint-license.sh",
  "sh ./bin/lint-shared-partials.sh",
  "sh ./bin/lint-script-invocation.sh",
  "sh ./bin/lint-agents-md-size.sh",
  "sh ./bin/lint-markdown-punctuation.sh",
  "sh ./bin/lint-skill-tests.sh",
  "sh ./bin/lint-mjs-syntax.sh",
];

function usageError(message) {
  process.stderr.write(`run-lints: ${message}\n`);
  process.exit(2);
}

const argv = process.argv.slice(2);
let steps = null;
let rawJobs = process.env.JOBS ?? "";
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--step" || argv[i] === "--jobs") {
    if (i + 1 >= argv.length) usageError(`${argv[i]} に値が必要です`);
    if (argv[i] === "--step") (steps ??= []).push(argv[++i]);
    else rawJobs = argv[++i];
  } else {
    usageError(`不明な引数: ${argv[i]}`);
  }
}
steps ??= DEFAULT_STEPS;
let jobs;
if (rawJobs === "") jobs = Math.max(1, os.availableParallelism());
else if (/^[1-9][0-9]*$/.test(rawJobs)) jobs = Number(rawJobs);
else usageError(`JOBS / --jobs は 1 以上の整数で指定してください: ${rawJobs}`);

const results = new Array(steps.length);
let next = 0;
let printed = 0;

function flush() {
  while (printed < steps.length && results[printed]) {
    const r = results[printed++];
    process.stdout.write(`+ ${r.cmd}\n${r.out}`);
  }
}

function runOne(index) {
  return new Promise((resolve) => {
    const cmd = steps[index];
    const child = spawn("sh", ["-c", cmd], { stdio: ["ignore", "pipe", "pipe"] });
    // 多バイト文字がチャンク境界で分断されないよう、Buffer を蓄積してから復号する
    const chunks = [];
    child.stdout.on("data", (d) => chunks.push(d));
    child.stderr.on("data", (d) => chunks.push(d));
    child.on("error", (e) => {
      results[index] = { cmd, out: `${e.message}\n`, code: 1 };
      flush();
      resolve();
    });
    child.on("close", (code) => {
      results[index] = { cmd, out: Buffer.concat(chunks).toString("utf8"), code: code ?? 1 };
      flush();
      resolve();
    });
  });
}

async function worker() {
  while (next < steps.length) await runOne(next++);
}

await Promise.all(Array.from({ length: Math.min(jobs, steps.length) }, worker));

const failed = results.filter((r) => r.code !== 0);
if (failed.length > 0) {
  process.stderr.write(`run-lints: ${failed.length} 件の lint が失敗しました\n`);
  for (const r of failed) process.stderr.write(`  FAIL: ${r.cmd}\n`);
  process.exit(1);
}
