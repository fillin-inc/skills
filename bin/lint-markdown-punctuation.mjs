// Markdown 括弧の全角/半角ルールを検証する。
//
// 本文で使う括弧は半角に統一する。全角括弧 `（` `）` は一律で違反として扱い、
// 「日本語のみなら全角可」「装飾意図があれば全角可」といった例外は設けない
// (主観判定を残すと機械検証できず、実際に守られないため)。
//
// 例外はインラインコード (`` `...` ``) だけ。全角であること自体が意味を持つ
// 記述 — ルール説明の `（`、NG 例の `IP アドレス（IPv4）`、全角→半角変換の
// 仕様説明 `（１）` → `(1)` など — がここに書かれるため。
//
// コードブロックと引用行は検査対象に含める:
//   - コードブロック: 生成物テンプレート本体 (`markdown` / `yaml` フェンス) は
//     成果物の見た目そのものの規定であり、全角を残すと生成物に混入する。
//     `bash` / `sh` フェンスの全角括弧もコメントか出力メッセージ内にしか現れず、
//     実行構文には影響しない
//   - 引用行: 本リポジトリの `>` は外部原文の引用ではなく `> **Note**:` 形式の
//     注記ブロックとして使われている
//
// 原文をそのまま残したい箇所はインラインコードで書く。
//
// 使い方 (通常は bin/lint-markdown-punctuation.sh 経由で呼ばれる):
//   node bin/lint-markdown-punctuation.mjs [--fix] <file>...
//
// exit code: 0 = 違反なし (または --fix で修正完了), 1 = 違反あり

import { readFileSync, writeFileSync } from 'node:fs';

const FULLWIDTH = /[（）]/g;

/**
 * インラインコード (`...`) を同じ長さの X で潰す。
 * 添字が保存されるので、元行への置換位置計算にそのまま使える。
 */
function maskInlineCode(line) {
  return line.replace(/`[^`]*`/g, (m) => 'X'.repeat(m.length));
}

/**
 * 1 行を処理し、置換後の行 / 違反数 / 最初の該当箇所を返す。
 *
 * 全角括弧を無条件に半角へ置換するため、開き / 閉じの対応を解決する必要がない。
 * 複数行にまたがる括弧も、各行を独立に置換すれば結果として整合する。
 */
function processLine(line) {
  const masked = maskInlineCode(line);
  const positions = [];
  let m;
  FULLWIDTH.lastIndex = 0;
  while ((m = FULLWIDTH.exec(masked)) !== null) positions.push(m.index);

  if (positions.length === 0) return { text: line, count: 0, hit: null };

  // maskInlineCode は長さを保存するので、masked の添字を元行にそのまま使える
  const hit = line[positions[0]];
  let text = line;
  for (const i of positions.slice().reverse()) {
    text = text.slice(0, i) + (text[i] === '（' ? '(' : ')') + text.slice(i + 1);
  }

  return { text, count: positions.length, hit };
}

export function scanFile(source, { fix = false } = {}) {
  const lines = source.split('\n');
  const violations = [];
  let changed = false;

  const outLines = lines.map((line, idx) => {
    if (!/[（）]/.test(line)) return line;

    const { text, count, hit } = processLine(line);
    if (count === 0) return line;

    violations.push({ line: idx + 1, text: line.trim(), hit, count });
    if (!fix) return line;

    changed = true;
    return text;
  });

  return { violations, fixed: changed ? outLines.join('\n') : null };
}

function main() {
  const argv = process.argv.slice(2);
  const fix = argv.includes('--fix');
  const files = argv.filter((a) => a !== '--fix');

  if (files.length === 0) {
    console.error('lint-markdown-punctuation: 検査対象ファイルが渡されていません');
    process.exit(1);
  }

  const found = [];
  let fixedFiles = 0;

  for (const file of files) {
    let source;
    try {
      source = readFileSync(file, 'utf8');
    } catch (err) {
      console.error(`lint-markdown-punctuation: 読み込み失敗: ${file} (${err.message})`);
      process.exit(1);
    }
    const { violations, fixed } = scanFile(source, { fix });
    if (fixed !== null) {
      writeFileSync(file, fixed);
      fixedFiles += 1;
    }
    for (const v of violations) found.push({ file, ...v });
  }

  const total = found.reduce((n, v) => n + v.count, 0);
  const fileCount = new Set(found.map((v) => v.file)).size;

  if (fix) {
    console.log(
      `lint-markdown-punctuation: FIXED (${total} 箇所 / ${fixedFiles} ファイルを半角へ置換)`,
    );
    return;
  }

  if (found.length === 0) {
    console.log(`lint-markdown-punctuation: PASS (${files.length} files checked)`);
    return;
  }

  console.error('lint-markdown-punctuation: FAIL');
  const SHOW = 50;
  for (const v of found.slice(0, SHOW)) {
    console.error(`  ${v.file}:${v.line}  ${v.text.slice(0, 100)}`);
  }
  if (found.length > SHOW) {
    console.error(`  ... 他 ${found.length - SHOW} 行`);
  }
  console.error(`  合計 ${total} 箇所 / ${fileCount} ファイルで全角括弧を検出しました。`);
  console.error('  括弧は半角に統一してください。原文を残したい箇所はインラインコード');
  console.error('  (`...`) で書きます — 全角であること自体が意味を持つ記述のみが例外です。');
  console.error('  一括修正: sh ./bin/lint-markdown-punctuation.sh --fix');
  process.exit(1);
}

// テストから import された場合は main を実行しない
if (process.argv[1] && process.argv[1].endsWith('lint-markdown-punctuation.mjs')) {
  main();
}
