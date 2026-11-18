#!/usr/bin/env node
// グラフィックレコーディング画像生成のオプションを解決し、
// 呼び出し側 (ホストエージェント) が読む形で標準出力へ書き出す。
//
// 出力形式:
//   KEY=VALUE 行のブロック。画風とレイアウトの本文は references/presets.md が
//   持ち、本スクリプトはどの節を読むかを指す見出し名だけを出す。
//
// 終了コード:
//   0  正常
//   64 引数エラー (usage)
//
// Node.js 22 以上、組み込みモジュールのみで動く。

import { statSync } from "node:fs";

const USAGE = `usage: parse-options.mjs [--tone business|standard|pop|mono]
                         [--orientation landscape|portrait]
                         [--output <path>]
                         [<入力テキストまたはファイルパス> ...]
`;

const TONES = ["business", "standard", "pop", "mono"];
const ORIENTATIONS = {
  landscape: { exact: "1.414:1", fallback: "4:3", fallbackAlt: "3:2", width: 1754, height: 1240 },
  portrait: { exact: "1:1.414", fallback: "3:4", fallbackAlt: "2:3", width: 1240, height: 1754 },
};

function die(message) {
  process.stderr.write(`parse-options.mjs: ${message}\n${USAGE}`);
  process.exit(64);
}

function isFile(p) {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

let tone = "standard";
let orientation = "landscape";
let output = "";
const inputFiles = [];
const inputText = [];

const args = process.argv.slice(2);
// `--flag <value>` の値を取る。値が無ければ usage エラー
const valueOf = (i, flag) => {
  if (i + 1 >= args.length) die(`${flag} に値がありません`);
  return args[i + 1];
};
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--tone") {
    tone = valueOf(i++, a);
  } else if (a.startsWith("--tone=")) {
    tone = a.slice("--tone=".length);
  } else if (a === "--orientation") {
    orientation = valueOf(i++, a);
  } else if (a.startsWith("--orientation=")) {
    orientation = a.slice("--orientation=".length);
  } else if (a === "--output") {
    output = valueOf(i++, a);
  } else if (a.startsWith("--output=")) {
    output = a.slice("--output=".length);
  } else if (a === "-h" || a === "--help") {
    process.stderr.write(USAGE);
    process.exit(0);
  } else if (a.startsWith("--")) {
    die(`未知のオプション: ${a}`);
  } else if (isFile(a)) {
    // 既存ファイルを指すなら入力ファイル、そうでなければ入力テキストとして扱う。
    inputFiles.push(a);
  } else {
    inputText.push(a);
  }
}

if (!TONES.includes(tone)) die(`--tone は business / standard / pop / mono のいずれかです: ${tone}`);
const o = Object.hasOwn(ORIENTATIONS, orientation) ? ORIENTATIONS[orientation] : null;
if (!o) die(`--orientation は landscape / portrait のいずれかです: ${orientation}`);

process.stdout.write(
  [
    `TONE=${tone}`,
    `ORIENTATION=${orientation}`,
    `ASPECT_EXACT=${o.exact}`,
    `ASPECT_FALLBACK=${o.fallback}`,
    `ASPECT_FALLBACK_ALT=${o.fallbackAlt}`,
    `PIXEL_WIDTH=${o.width}`,
    `PIXEL_HEIGHT=${o.height}`,
    `OUTPUT_PATH=${output}`,
    `INPUT_FILES=${inputFiles.join(" ")}`,
    `INPUT_TEXT=${inputText.join(" ")}`,
    `STYLE_SECTION=## トーン: ${tone}`,
    `LAYOUT_SECTION=## 向き: ${orientation}`,
    "",
  ].join("\n"),
);
