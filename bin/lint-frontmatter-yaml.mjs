#!/usr/bin/env node
// SKILL.md の frontmatter を YAML として検証する。
// - ライブラリ: lint-frontmatter.mjs が validateFrontmatter() を import して使う
// - CLI: node lint-frontmatter-yaml.mjs --check-deps | <file> <closing-line>
//
// license は値の型(空でない文字列)だけを検証する。値の妥当性(SPDX 識別子と
// 同梱 LICENSE 本文の整合)は bin/lint-license.sh が担う。

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const DEPS_MESSAGE =
  "lint-frontmatter-yaml.mjs: yaml package が見つかりません。make install-node-deps を実行してください";

export async function loadYaml() {
  try {
    return await import("yaml");
  } catch {
    return null;
  }
}

// 戻り値: エラーメッセージの配列(空なら妥当)
export function validateFrontmatter(yaml, file, lines, closingLine) {
  const { isMap, parseDocument } = yaml;
  const source = lines.slice(1, closingLine - 1).join("\n");
  const document = parseDocument(source, {
    prettyErrors: true,
    strict: true,
    stringKeys: true,
    uniqueKeys: true,
  });

  if (document.errors.length > 0) {
    return document.errors.map((error) => {
      const sourceLine = error.linePos?.[0]?.line;
      const location = sourceLine ? `:${sourceLine + 1}` : "";
      const message = error.message.split("\n", 1)[0];
      return `${file}${location}: invalid YAML (${error.code}): ${message}`;
    });
  }

  if (!isMap(document.contents)) {
    return [`${file}: frontmatter must be a YAML mapping`];
  }

  const frontmatter = document.toJS();
  if (
    Object.hasOwn(frontmatter, "license") &&
    (typeof frontmatter.license !== "string" || frontmatter.license.trim() === "")
  ) {
    return [`${file}: license must be a non-empty string (e.g. MIT)`];
  }
  return [];
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const yaml = await loadYaml();
  if (!yaml) {
    console.error(DEPS_MESSAGE);
    process.exit(2);
  }
  if (process.argv[2] === "--check-deps") process.exit(0);

  const [, , file, closingLineText] = process.argv;
  const closingLine = Number(closingLineText);
  if (!file || !Number.isInteger(closingLine) || closingLine < 2) {
    console.error("lint-frontmatter-yaml.mjs: file and closing delimiter line are required");
    process.exit(2);
  }
  const lines = readFileSync(file, "utf8").split(/\r?\n/);
  const errors = validateFrontmatter(yaml, file, lines, closingLine);
  for (const e of errors) console.error(e);
  process.exit(errors.length > 0 ? 1 : 0);
}
