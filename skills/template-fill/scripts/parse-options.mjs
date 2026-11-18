#!/usr/bin/env node
// template-fill のオプションを解決し、呼び出し側 (ホストエージェント) が読む
// KEY=VALUE 形式で標準出力へ書き出す。
//
// 終了コード:
//   0  正常
//   64 引数エラー (usage)
//   66 テンプレートが見つからない / 読めない
//
// Node.js 22 以上、組み込みモジュールのみで動く。

import { accessSync, constants, existsSync, statSync } from "node:fs";
import path from "node:path";

const USAGE = "usage: parse-options.mjs <template.md> [--output <path>]\n";

function die(message) {
  process.stderr.write(`parse-options.mjs: ${message}\n${USAGE}`);
  process.exit(64);
}

function isReadableFile(p) {
  try {
    if (!statSync(p).isFile()) return false;
    accessSync(p, constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

// date +%Y-%m-%d と同じくローカル時刻の日付
function today() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

let template = "";
let output = "";

const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--output") {
    if (i + 1 >= args.length) die("--output に値がありません");
    output = args[++i];
  } else if (a.startsWith("--output=")) {
    output = a.slice("--output=".length);
  } else if (a === "-h" || a === "--help") {
    process.stderr.write(USAGE);
    process.exit(0);
  } else if (a.startsWith("--")) {
    die(`未知のオプション: ${a}`);
  } else {
    if (template !== "") die(`テンプレートは 1 つだけ指定できます: ${a}`);
    template = a;
  }
}

if (template === "") die("テンプレートを指定してください");

if (!/\.(md|markdown)$/.test(template.toLowerCase())) {
  die(`テンプレートは Markdown (.md / .markdown) のみ対応しています: ${template}`);
}

if (!isReadableFile(template)) {
  process.stderr.write(`parse-options.mjs: テンプレートが見つからないか読めません: ${template}\n`);
  process.exit(66);
}

if (output !== "") {
  if (existsSync(output)) die(`出力先が既に存在します (上書きしません): ${output}`);
} else {
  // テンプレート名 + 当日の日付で作業ディレクトリに置く。既存ファイルは上書きしない。
  const stem = path.basename(template);
  const base = `${stem.slice(0, stem.lastIndexOf("."))}-${today()}`;
  output = `${base}.md`;
  for (let n = 2; existsSync(output); n++) output = `${base}-${n}.md`;
}

process.stdout.write(`TEMPLATE=${template}\nOUTPUT_PATH=${output}\n`);
