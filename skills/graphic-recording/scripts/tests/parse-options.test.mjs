// parse-options の出力・終了コードの回帰テスト。
// 期待値は Node.js 移行前の parse-options.sh の出力を基準にしている。
// PARSE_OPTIONS_SCRIPT に別実装のパス (.sh なら sh、それ以外は node で起動) を渡すと、同じ期待値で検証できる。

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT = path.resolve(process.env.PARSE_OPTIONS_SCRIPT || path.join(HERE, "..", "parse-options.mjs"));
const [CMD, ...CMD_ARGS] = [SCRIPT.endsWith(".sh") ? "sh" : "node", SCRIPT];

const WORK = mkdtempSync(path.join(os.tmpdir(), "graphic-recording-parse-options-"));
after(() => rmSync(WORK, { recursive: true, force: true }));
writeFileSync(path.join(WORK, "in.txt"), "x");

const run = (...args) => {
  const r = spawnSync(CMD, [...CMD_ARGS, ...args], { cwd: WORK, encoding: "utf8" });
  return { code: r.status, out: r.stdout, err: r.stderr };
};

const expected = (o) =>
  [
    `TONE=${o.tone}`,
    `ORIENTATION=${o.orientation}`,
    `ASPECT_EXACT=${o.orientation === "landscape" ? "1.414:1" : "1:1.414"}`,
    `ASPECT_FALLBACK=${o.orientation === "landscape" ? "4:3" : "3:4"}`,
    `ASPECT_FALLBACK_ALT=${o.orientation === "landscape" ? "3:2" : "2:3"}`,
    `PIXEL_WIDTH=${o.orientation === "landscape" ? 1754 : 1240}`,
    `PIXEL_HEIGHT=${o.orientation === "landscape" ? 1240 : 1754}`,
    `OUTPUT_PATH=${o.output ?? ""}`,
    `INPUT_FILES=${o.files ?? ""}`,
    `INPUT_TEXT=${o.text ?? ""}`,
    `STYLE_SECTION=## トーン: ${o.tone}`,
    `LAYOUT_SECTION=## 向き: ${o.orientation}`,
    "",
  ].join("\n");

test("引数なしは standard / landscape の既定値を出す", () => {
  const r = run();
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out, expected({ tone: "standard", orientation: "landscape" }));
});

test("空白区切りの値指定と入力テキストを解決する", () => {
  const r = run("--tone", "pop", "--orientation", "portrait", "--output", "out.png", "hello", "world");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out,
    expected({ tone: "pop", orientation: "portrait", output: "out.png", text: "hello world" }),
  );
});

test("= 区切りの値指定と、既存ファイルとテキストの振り分け", () => {
  const r = run("--tone=mono", "--orientation=landscape", "in.txt", "more", "text", "in.txt");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out,
    expected({ tone: "mono", orientation: "landscape", files: "in.txt in.txt", text: "more text" }),
  );
});

test("business トーンを受け付ける", () => {
  const r = run("--tone", "business");
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out, expected({ tone: "business", orientation: "landscape" }));
});

for (const [desc, args, pattern] of [
  ["不正な --tone", ["--tone", "bad"], /--tone は business \/ standard \/ pop \/ mono のいずれかです: bad/],
  ["空の --tone=", ["--tone="], /--tone は business/],
  ["不正な --orientation", ["--orientation", "square"], /--orientation は landscape \/ portrait のいずれかです: square/],
  ["値の無い --tone", ["--tone"], /--tone に値がありません/],
  ["値の無い --orientation", ["--orientation"], /--orientation に値がありません/],
  ["値の無い --output", ["--output"], /--output に値がありません/],
  ["未知のオプション", ["--zzz"], /未知のオプション: --zzz/],
]) {
  test(`${desc} は exit 64 で usage を出す`, () => {
    const r = run(...args);
    assert.equal(r.code, 64);
    assert.equal(r.out, "");
    assert.match(r.err, pattern);
    assert.match(r.err, /^usage: parse-options/m);
  });
}

test("-h / --help は exit 0 で usage を stderr に出す", () => {
  for (const flag of ["-h", "--help"]) {
    const r = run(flag);
    assert.equal(r.code, 0);
    assert.equal(r.out, "");
    assert.match(r.err, /^usage: parse-options/m);
  }
});
