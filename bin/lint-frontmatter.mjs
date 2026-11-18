#!/usr/bin/env node
// SKILL.md の YAML frontmatter を agentskills.io 仕様と既存の YAML エスケープ規約で検証する。
// 検証内容の一覧は lint-frontmatter.sh(薄いラッパー)の冒頭コメントを参照。
// 1 プロセスで全 SKILL.md を検査する(ファイルごとのプロセス起動を避けて高速化)。
//
// 使い方: node bin/lint-frontmatter.mjs   (cwd 配下の SKILL.md を検査)

import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { loadYaml, validateFrontmatter } from "./lint-frontmatter-yaml.mjs";

const BODY_LINE_LIMIT = 500;
const ALLOWED_FIELDS = new Set([
  "name", "description", "argument-hint", "license", "compatibility",
  "metadata", "allowed-tools", "model", "effort",
]);
const EXCLUDED_TOP = new Set([".claude", ".agents", ".git"]);

const yaml = await loadYaml();
if (!yaml) {
  console.error(
    "lint-frontmatter-yaml.mjs: yaml package が見つかりません。make install-node-deps を実行してください",
  );
  process.exit(1);
}

const errors = [];
const warnings = [];
const emitErr = (m) => { process.stderr.write(`${m}\n`); errors.push(m); };
const emitWarn = (m) => { process.stderr.write(`${m}\n`); warnings.push(m); };

function findSkillMds(dir, rel, out) {
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    if (ent.name === "node_modules") continue;
    if (rel === "." && EXCLUDED_TOP.has(ent.name)) continue;
    const childRel = `${rel}/${ent.name}`;
    if (ent.isDirectory()) findSkillMds(path.join(dir, ent.name), childRel, out);
    else if (ent.name === "SKILL.md" && ent.isFile()) out.push(childRel);
  }
}

function stripQuotes(v) {
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) return v.slice(1, -1);
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) return v.slice(1, -1);
  return v;
}

function validateName(file, lineno, name) {
  const len = [...name].length;
  if (len < 1 || len > 64) {
    emitErr(`${file}:${lineno}: name length must be 1-64 (got ${len}): ${name}`);
    return;
  }
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name)) {
    emitErr(
      `${file}:${lineno}: name must be kebab-case (lowercase a-z, 0-9, hyphens; no leading/trailing/consecutive hyphens): ${name}`,
    );
  }
}

function checkFile(file) {
  const expectedName = path.basename(path.dirname(file));
  const text = readFileSync(file, "utf8");
  const lines = text.split("\n");
  if (lines[lines.length - 1] === "") lines.pop();

  if (lines[0] !== "---") {
    emitErr(`${file}:1: first line must be the opening frontmatter delimiter ---`);
    return;
  }
  let closing = 0;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === "---") { closing = i + 1; break; }
  }
  if (closing === 0) {
    emitErr(`${file}: missing closing frontmatter delimiter ---`);
    return;
  }

  const yamlErrors = validateFrontmatter(yaml, file, text.split(/\r?\n/), closing);
  if (yamlErrors.length > 0) {
    emitErr(yamlErrors.join("\n"));
    return;
  }

  let haveName = false;
  let haveDesc = false;
  let haveLicense = false;
  for (let lineno = 2; lineno < closing; lineno++) {
    const line = lines[lineno - 1];
    const m = /^[a-zA-Z_-]*: */.exec(line);
    const value = m ? line.slice(m[0].length) : "";
    if (value.startsWith('"') || value.startsWith("'")) {
      // quoted: OK
    } else if (value.startsWith("[")) {
      emitErr(`${file}:${lineno}: unquoted value starting with "[" — wrap in double quotes: ${value}`);
    } else if (value.includes(": ")) {
      emitErr(`${file}:${lineno}: unquoted value contains ": " — wrap in double quotes or rephrase: ${value}`);
    }

    const km = /^([^:\s]+):/.exec(line);
    if (!km) continue;
    const key = km[1];
    const rawVal = line.replace(/^[^:\s]+: */, "");
    const val = stripQuotes(rawVal);

    if (!ALLOWED_FIELDS.has(key)) {
      emitWarn(`${file}:${lineno}: WARN: unknown frontmatter field (not in allowlist): ${key}`);
      continue;
    }
    if (key === "name") {
      haveName = true;
      validateName(file, lineno, val);
      if (val !== expectedName) {
        emitErr(`${file}:${lineno}: name "${val}" must match parent directory name "${expectedName}"`);
      }
    } else if (key === "description") {
      haveDesc = true;
      if (rawVal.startsWith("|") || rawVal.startsWith(">")) {
        emitErr(
          `${file}:${lineno}: description must be a single-line scalar (YAML block scalar (pipe or folded) is not supported by this linter)`,
        );
      } else {
        // locale 依存を避けるため byte 長で判定する
        const dlen = Buffer.byteLength(val, "utf8");
        if (dlen < 1 || dlen > 1024) {
          emitErr(`${file}:${lineno}: description length must be 1-1024 bytes (got ${dlen})`);
        }
      }
    } else if (key === "license") {
      haveLicense = true;
    }
  }

  if (!haveName) emitErr(`${file}: missing required field: name`);
  if (!haveDesc) emitErr(`${file}: missing required field: description`);
  if (!haveLicense) {
    emitErr(`${file}: missing required field: license (required by this repository, see AGENTS.md)`);
  }
  const bodyLines = lines.length - closing;
  if (bodyLines > BODY_LINE_LIMIT) {
    emitErr(`${file}: SKILL.md body is ${bodyLines} lines (max: ${BODY_LINE_LIMIT}). Move details into references/ files.`);
  }
}

const files = [];
findSkillMds(".", ".", files);
files.sort();
for (const f of files) checkFile(f);

const lineCount = (arr) => arr.reduce((n, m) => n + m.split("\n").length, 0);
if (warnings.length > 0) process.stderr.write(`\n${lineCount(warnings)} warning(s) found\n`);
if (errors.length > 0) {
  process.stderr.write(`\n${lineCount(errors)} error(s) found\n`);
  process.exit(1);
}
console.log("frontmatter: ok");
