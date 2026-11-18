#!/usr/bin/env node
// make test の runner。bin/tests と skill 同梱テストを列挙し、並列に実行する。
//
// 使い方: node bin/run-tests.mjs [--skills <name,...>] [--jobs <N>] [--quiet] [--list] [--root <dir>]
//   --skills  対象を skill 名で絞る(カンマまたは空白区切り)。対象は次の和集合
//             - その skill の同梱テスト
//             - bin/tests/test-map.tsv で skill に対応づけた bin/tests
//   --jobs    同時実行数。既定は JOBS 環境変数、なければ os.availableParallelism()。1 で逐次
//   --quiet   成功したテストの出力を省く(失敗は常に全文を出す)
//   --list    実行せず、対象のテストを 1 行 1 件で出す
//   --root    リポジトリルート(既定: 本ファイルの 1 つ上)
// 終了コード: 0 = 全件成功(対象 0 件を含む)、1 = 失敗あり、2 = 引数不正

import { spawn, spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));

function usageError(message) {
  process.stderr.write(`run-tests: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { skills: null, jobs: null, quiet: false, list: false, root: path.resolve(HERE, "..") };
  const takeValue = (i, flag) => {
    if (i + 1 >= argv.length) usageError(`${flag} に値が必要です`);
    return argv[i + 1];
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--skills") {
      opts.skills = (opts.skills ?? []).concat(takeValue(i++, a).split(/[\s,]+/).filter(Boolean));
    } else if (a === "--jobs") {
      opts.jobs = takeValue(i++, a);
    } else if (a === "--root") {
      opts.root = path.resolve(takeValue(i++, a));
    } else if (a === "--quiet") {
      opts.quiet = true;
    } else if (a === "--list") {
      opts.list = true;
    } else {
      usageError(`不明な引数: ${a}`);
    }
  }
  if (opts.skills !== null && opts.skills.length === 0) opts.skills = null;
  const rawJobs = opts.jobs ?? process.env.JOBS ?? "";
  if (rawJobs === "") {
    opts.jobs = Math.max(1, os.availableParallelism());
  } else if (/^[1-9][0-9]*$/.test(rawJobs)) {
    opts.jobs = Number(rawJobs);
  } else {
    usageError(`JOBS / --jobs は 1 以上の整数で指定してください: ${rawJobs}`);
  }
  return opts;
}

function readTsv(file) {
  if (!existsSync(file)) return [];
  return readFileSync(file, "utf8")
    .split("\n")
    .filter((l) => l !== "" && !l.startsWith("#"))
    .map((l) => l.split("\t"));
}

function listBinTests(root) {
  const dir = path.join(root, "bin", "tests");
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => /^test-.*\.(sh|mjs)$/.test(f))
    .sort()
    .map((f) => `bin/tests/${f}`);
}

function listSkillTests(root) {
  const r = spawnSync("sh", [path.join(HERE, "list-skill-tests.sh"), root], { encoding: "utf8" });
  if (r.status !== 0) usageError(`list-skill-tests.sh が失敗しました: ${r.stderr}`);
  return r.stdout.split("\n").filter(Boolean).map((f) => f);
}

function commandFor(test) {
  if (test.endsWith(".test.mjs")) return ["node", ["--test", test]];
  if (test.endsWith(".mjs")) return ["node", [test]];
  return ["bash", [test]];
}

// skill は skills/<name>/ と skills/<group>/<name>/ のどちらにも置ける。SKILL.md のある階層を skill とみなす
function skillOf(root, file) {
  const parts = file.split("/");
  if (parts[0] !== "skills" || parts.length < 3) return null;
  if (existsSync(path.join(root, "skills", parts[1], "SKILL.md"))) return parts[1];
  if (parts.length >= 4 && existsSync(path.join(root, "skills", parts[1], parts[2], "SKILL.md"))) return parts[2];
  return null;
}

// skill 名の Set。skills/<name>/SKILL.md と skills/<group>/<name>/SKILL.md を拾う
function skillNames(root) {
  const names = new Set();
  const dir = path.join(root, "skills");
  if (!existsSync(dir)) return names;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    if (existsSync(path.join(dir, e.name, "SKILL.md"))) {
      names.add(e.name);
      continue;
    }
    for (const c of readdirSync(path.join(dir, e.name), { withFileTypes: true })) {
      if (c.isDirectory() && existsSync(path.join(dir, e.name, c.name, "SKILL.md"))) names.add(c.name);
    }
  }
  return names;
}

// bin/tests のテスト -> 関係する skill 名の Set
function binTestSkills(root) {
  const result = new Map();
  for (const [test, skills = "-"] of readTsv(path.join(root, "bin", "tests", "test-map.tsv"))) {
    result.set(test, new Set(skills === "-" ? [] : skills.split(",").filter(Boolean)));
  }
  return result;
}

function selectTests(opts) {
  const binTests = listBinTests(opts.root);
  const skillTests = listSkillTests(opts.root);
  if (opts.skills === null) return [...binTests, ...skillTests];

  const known = skillNames(opts.root);
  const unknown = opts.skills.filter((s) => !known.has(s));
  if (unknown.length > 0) usageError(`存在しない skill: ${unknown.join(", ")}`);
  const wanted = new Set(opts.skills);
  const map = binTestSkills(opts.root);
  const picked = [];
  for (const t of binTests) {
    const set = map.get(t);
    if (set === undefined) {
      process.stderr.write(`run-tests: ${t} が bin/tests/test-map.tsv に無いため絞り込みでは実行しません\n`);
    } else if ([...set].some((s) => wanted.has(s))) {
      picked.push(t);
    }
  }
  for (const t of skillTests) if (wanted.has(skillOf(opts.root, t))) picked.push(t);
  return picked;
}

function runOne(root, test) {
  return new Promise((resolve) => {
    const [cmd, args] = commandFor(test);
    const started = process.hrtime.bigint();
    const chunks = [];
    const done = (code, extra = "") => {
      const ms = Number(process.hrtime.bigint() - started) / 1e6;
      resolve({ test, code, ms, output: Buffer.concat(chunks).toString("utf8") + extra });
    };
    let child;
    try {
      child = spawn(cmd, args, { cwd: root, stdio: ["ignore", "pipe", "pipe"], env: process.env });
    } catch (e) {
      done(127, `${e.message}\n`);
      return;
    }
    child.stdout.on("data", (d) => chunks.push(d));
    child.stderr.on("data", (d) => chunks.push(d));
    child.on("error", (e) => done(127, `${e.message}\n`));
    child.on("close", (code, signal) => done(code ?? 128, signal ? `terminated by ${signal}\n` : ""));
  });
}

const fmt = (ms) => `${(ms / 1000).toFixed(1)}s`;

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const tests = selectTests(opts);
  if (opts.list) {
    for (const t of tests) process.stdout.write(`${t}\n`);
    return 0;
  }
  if (tests.length === 0) {
    process.stdout.write("run-tests: 対象のテストがありません\n");
    return 0;
  }
  const jobs = Math.min(opts.jobs, tests.length);
  process.stdout.write(`run-tests: ${tests.length} files, jobs=${jobs}\n`);

  const started = Date.now();
  const results = [];
  let next = 0;
  const worker = async () => {
    while (next < tests.length) {
      const test = tests[next++];
      const r = await runOne(opts.root, test);
      results.push(r);
      // 1 テストの出力は完了時にまとめて 1 回で書き、ほかのテストの出力と混ぜない
      const status = r.code === 0 ? "ok" : `FAIL (exit ${r.code})`;
      let block = `==> ${r.test} [${status}, ${fmt(r.ms)}]\n`;
      if (r.code !== 0 || !opts.quiet) {
        block += r.output.endsWith("\n") || r.output === "" ? r.output : `${r.output}\n`;
      }
      process.stdout.write(block);
    }
  };
  await Promise.all(Array.from({ length: jobs }, worker));

  const failed = results.filter((r) => r.code !== 0).sort((a, b) => a.test.localeCompare(b.test));
  const slowest = [...results].sort((a, b) => b.ms - a.ms).slice(0, 5);
  process.stdout.write(`\nrun-tests: slowest ${slowest.length}\n`);
  for (const r of slowest) process.stdout.write(`  ${fmt(r.ms).padStart(7)}  ${r.test}\n`);
  const elapsed = fmt(Date.now() - started);
  if (failed.length > 0) {
    process.stdout.write(`\nrun-tests: FAIL (${failed.length} / ${results.length} files, ${elapsed})\n`);
    for (const r of failed) process.stdout.write(`  ${r.test} (exit ${r.code})\n`);
    return 1;
  }
  process.stdout.write(`\nrun-tests: PASS (${results.length} files, ${elapsed})\n`);
  return 0;
}

process.exitCode = await main();
