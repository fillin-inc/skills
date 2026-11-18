#!/usr/bin/env node
// 共通 partial のマニフェスト(bin/shared-partials.tsv)に基づき、各 SKILL.md の
// partial マーカー間内容が SSOT partial と byte 同一かを検証する。
// 仕様の詳細は lint-shared-partials.sh(薄いラッパー)の冒頭コメントを参照。
//
// 登録漏れの検査: スキャン対象ディレクトリ(既定は skills/)配下の md にある partial
// マーカーが、マニフェストに (partial id, 埋め込み先) として登録されていなければ error。
// マニフェストを引数で上書きしたときは、第 2 引数でスキャン対象を指定したときだけ検査する。
//
// 使い方: node bin/lint-shared-partials.mjs [<manifest.tsv> [<scan-dir>]]

import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const top = spawnSync("git", ["-C", HERE, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
if (top.status !== 0) {
  process.stderr.write("lint-shared-partials: リポジトリルートを取得できない\n");
  process.exit(1);
}
const REPO_ROOT = top.stdout.trim();
const manifest = process.argv[2] ?? path.join(REPO_ROOT, "bin", "shared-partials.tsv");

const err = (m) => process.stderr.write(`${m}\n`);

if (!isFile(manifest)) {
  err(`lint-shared-partials: マニフェストが見つからない: ${manifest}`);
  process.exit(1);
}
const scanArg = process.argv[3] ?? (process.argv[2] === undefined ? "skills" : null);
process.chdir(REPO_ROOT);

function isFile(p) {
  try { return statSync(p).isFile(); } catch { return false; }
}

// git hash-object 相当(blob の SHA-1)
function blobHash(buf) {
  const h = createHash("sha1");
  h.update(`blob ${buf.length}\0`);
  h.update(buf);
  return h.digest("hex");
}

const fileLines = (text) => {
  const lines = text.split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return lines;
};

const countMarkers = (lines, id) =>
  `${lines.filter((l) => l === `<!-- @partial:${id} start -->`).length} ${
    lines.filter((l) => l === `<!-- @partial:${id} end -->`).length
  }`;

// start 行から最初の end 行まで(end が無ければ EOF まで)を返す
function extractBlock(lines, id) {
  const out = [];
  let inBlock = false;
  for (const l of lines) {
    if (l === `<!-- @partial:${id} start -->`) { inBlock = true; out.push(l); continue; }
    if (l === `<!-- @partial:${id} end -->` && inBlock) { out.push(l); break; }
    if (inBlock) out.push(l);
  }
  return out;
}

let fail = false;
let checked = 0;
const registered = new Set(); // `${id}\0${resolved target}`
const cache = new Map();
const read = (p) => {
  if (!cache.has(p)) cache.set(p, readFileSync(p));
  return cache.get(p);
};

for (const raw of readFileSync(manifest, "utf8").split("\n")) {
  if (raw === "" || raw.startsWith("#")) continue;
  const tab = raw.indexOf("\t");
  const partial = tab < 0 ? raw : raw.slice(0, tab);
  const target = tab < 0 ? "" : raw.slice(tab + 1).replace(/^\t+/, "");
  if (partial === "" || partial.startsWith("#")) continue;

  if (target === "") {
    err(`lint-shared-partials: 不正な行 (TARGET_PATH 欠落): ${partial}`);
    fail = true;
    continue;
  }
  checked++;

  if (!isFile(partial)) {
    err(`lint-shared-partials: partial SSOT が存在しない: ${partial}`);
    fail = true;
    continue;
  }
  if (!isFile(target)) {
    err(`lint-shared-partials: 埋め込み先が存在しない: ${target} (partial: ${partial})`);
    fail = true;
    continue;
  }

  const partialBuf = read(partial);
  const partialLines = fileLines(partialBuf.toString("utf8"));
  const idm = /^<!-- @partial:([A-Za-z0-9_-]+) start -->$/.exec(partialLines[0] ?? "");
  const id = idm ? idm[1] : "";
  if (!id) {
    err(`lint-shared-partials: partial 先頭行に <!-- @partial:<id> start --> が無い: ${partial}`);
    fail = true;
    continue;
  }
  const endMarker = `<!-- @partial:${id} end -->`;
  if (!partialLines.includes(endMarker)) {
    err(`lint-shared-partials: partial SSOT に対応する終了マーカー (${endMarker}) が無い: ${partial}`);
    fail = true;
    continue;
  }
  registered.add(`${id}\0${path.resolve(target)}`);
  const targetLines = fileLines(read(target).toString("utf8"));
  if (!targetLines.includes(endMarker)) {
    err(`lint-shared-partials: 埋め込み先に対応する終了マーカー (${endMarker}) が無い: ${target}`);
    fail = true;
    continue;
  }

  // start / end マーカーがそれぞれ丁度 1 個であることを検証する(重複による
  // drift の見逃しを防ぐ)
  const pc = countMarkers(partialLines, id);
  if (pc !== "1 1") {
    err(`lint-shared-partials: partial SSOT のマーカー数が (1,1) ではない: ${partial} (start end = ${pc})`);
    fail = true;
    continue;
  }
  const tc = countMarkers(targetLines, id);
  if (tc !== "1 1") {
    err(`lint-shared-partials: 埋め込み先のマーカー数が (1,1) ではない: ${target} (start end = ${tc})`);
    fail = true;
    continue;
  }

  // シェルの $(...) と同じく末尾の改行を落としてから 1 個付ける
  const extracted = extractBlock(targetLines, id).join("\n").replace(/\n+$/, "");
  if (extracted === "") {
    err(`lint-shared-partials: 埋め込みマーカーが見つからない: ${target} (partial id: ${id})`);
    fail = true;
    continue;
  }

  const extractedBuf = Buffer.from(`${extracted}\n`, "utf8");
  if (!partialBuf.equals(extractedBuf)) {
    err("lint-shared-partials: drift 検出");
    err(`  partial SSOT: ${partial} (${blobHash(partialBuf)})`);
    err(`  target      : ${target} [${id}] (${blobHash(extractedBuf)})`);
    fail = true;
  }
}

// マニフェストに無い埋め込み(登録漏れ)を検出する
function* walkMd(dir) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (e.name === "node_modules" || e.name === ".git") continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) yield* walkMd(full);
    else if (e.isFile() && e.name.endsWith(".md")) yield full;
  }
}

if (scanArg !== null) {
  const markerRe = /^<!-- @partial:([A-Za-z0-9_-]+) (?:start|end) -->$/;
  for (const file of walkMd(scanArg)) {
    const ids = new Set();
    for (const l of fileLines(readFileSync(file, "utf8"))) {
      const m = markerRe.exec(l);
      if (m) ids.add(m[1]);
    }
    for (const id of ids) {
      if (!registered.has(`${id}\0${path.resolve(file)}`)) {
        err(`lint-shared-partials: マニフェスト未登録の partial マーカー: ${file} [${id}] (bin/shared-partials.tsv に追加する)`);
        fail = true;
      }
    }
  }
}

if (checked === 0 && !fail) {
  console.log(`lint-shared-partials: マニフェストに有効な行がない (partial 未登録): ${manifest}`);
  process.exit(0);
}
if (fail) {
  err("lint-shared-partials: FAIL");
  process.exit(1);
}
console.log(`lint-shared-partials: PASS (${checked} embeddings checked)`);
