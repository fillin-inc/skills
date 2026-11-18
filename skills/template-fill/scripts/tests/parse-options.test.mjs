// parse-options の出力・終了コードの回帰テスト。
// 期待値は Node.js 移行前の parse-options.sh の出力を基準にしている。
// PARSE_OPTIONS_SCRIPT に別実装のパス (.sh なら sh、それ以外は node で起動) を渡すと、同じ期待値で検証できる。

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT = path.resolve(process.env.PARSE_OPTIONS_SCRIPT || path.join(HERE, "..", "parse-options.mjs"));
const [CMD, ...CMD_ARGS] = [SCRIPT.endsWith(".sh") ? "sh" : "node", SCRIPT];

const SANDBOX = mkdtempSync(path.join(os.tmpdir(), "template-fill-parse-options-"));
after(() => rmSync(SANDBOX, { recursive: true, force: true }));

let seq = 0;
function workdir(files = {}) {
  const dir = path.join(SANDBOX, `w${seq++}`);
  mkdirSync(dir, { recursive: true });
  for (const [name, content] of Object.entries(files)) writeFileSync(path.join(dir, name), content);
  return dir;
}

const run = (cwd, ...args) => {
  const r = spawnSync(CMD, [...CMD_ARGS, ...args], { cwd, encoding: "utf8" });
  return { code: r.status, out: r.stdout, err: r.stderr };
};

// date +%Y-%m-%d と同じくローカル時刻の日付
const today = () => {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
};

test("--output なしはテンプレート名と日付から出力先を決める", () => {
  const cwd = workdir({ "Daily.MD": "# t\n" });
  const r = run(cwd, "Daily.MD");
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out, `TEMPLATE=Daily.MD\nOUTPUT_PATH=Daily-${today()}.md\n`);
});

test("既存ファイルと重なる出力先は -2, -3 と番号を付ける", () => {
  const cwd = workdir({
    "daily.md": "# t\n",
    [`daily-${today()}.md`]: "",
    [`daily-${today()}-2.md`]: "",
  });
  const r = run(cwd, "daily.md");
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out, `TEMPLATE=daily.md\nOUTPUT_PATH=daily-${today()}-3.md\n`);
});

test("サブディレクトリのテンプレートは basename から出力先を決める", () => {
  const cwd = workdir();
  mkdirSync(path.join(cwd, "tpl"));
  writeFileSync(path.join(cwd, "tpl", "weekly.markdown"), "# w\n");
  const r = run(cwd, "tpl/weekly.markdown");
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out, `TEMPLATE=tpl/weekly.markdown\nOUTPUT_PATH=weekly-${today()}.md\n`);
});

test("--output は空白区切りと = 区切りのどちらも受け付ける", () => {
  const cwd = workdir({ "t.md": "# t\n" });
  for (const args of [["t.md", "--output", "o.md"], ["--output=o.md", "t.md"]]) {
    const r = run(cwd, ...args);
    assert.equal(r.code, 0, r.err);
    assert.equal(r.out, "TEMPLATE=t.md\nOUTPUT_PATH=o.md\n");
  }
});

for (const [desc, files, args, pattern] of [
  ["テンプレート未指定", {}, [], /テンプレートを指定してください/],
  ["Markdown 以外", { "a.txt": "" }, ["a.txt"], /Markdown \(\.md \/ \.markdown\) のみ対応しています: a\.txt/],
  ["テンプレートの複数指定", { "t.md": "" }, ["t.md", "t.md"], /テンプレートは 1 つだけ指定できます: t\.md/],
  ["既存の出力先", { "t.md": "", "o.md": "" }, ["t.md", "--output", "o.md"], /出力先が既に存在します \(上書きしません\): o\.md/],
  ["値の無い --output", {}, ["--output"], /--output に値がありません/],
  ["未知のオプション", {}, ["--zzz"], /未知のオプション: --zzz/],
]) {
  test(`${desc} は exit 64 で usage を出す`, () => {
    const r = run(workdir(files), ...args);
    assert.equal(r.code, 64);
    assert.equal(r.out, "");
    assert.match(r.err, pattern);
    assert.match(r.err, /^usage: parse-options/m);
  });
}

test("存在しないテンプレートは exit 66", () => {
  const r = run(workdir(), "missing.md");
  assert.equal(r.code, 66);
  assert.equal(r.out, "");
  assert.match(r.err, /テンプレートが見つからないか読めません: missing\.md/);
});

test("ディレクトリを指すテンプレートは exit 66", () => {
  const cwd = workdir();
  mkdirSync(path.join(cwd, "dir.md"));
  const r = run(cwd, "dir.md");
  assert.equal(r.code, 66);
});

test("-h / --help は exit 0 で usage を stderr に出す", () => {
  for (const flag of ["-h", "--help"]) {
    const r = run(workdir(), flag);
    assert.equal(r.code, 0);
    assert.equal(r.out, "");
    assert.match(r.err, /^usage: parse-options/m);
  }
});
