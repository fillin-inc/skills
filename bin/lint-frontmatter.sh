#!/bin/sh
# SKILL.md の YAML frontmatter を agentskills.io 仕様 (https://agentskills.io/specification) と
# 既存の YAML エスケープ規約に基づいて検証する。
#
# 実体は lint-frontmatter.mjs(1 プロセスで全 SKILL.md を検査する)。
#
# 検証内容:
#   frontmatter 構造:
#     - 1 行目と closing delimiter が `---` であることを確認
#     - YAML 構文と mapping key の重複を Node.js の YAML parser で検証
#   YAML エスケープ:
#     - 値が [ で始まる場合、ダブルクォートで囲まれていることを確認
#     - unquoted な値に ": "（コロン+空白）が含まれていないことを確認
#   agentskills.io 仕様:
#     - name は kebab-case (a-z, 0-9, ハイフン)、1-64 文字、連続/先頭/末尾ハイフン禁止
#     - SKILL.md の親ディレクトリ名 = name field 一致
#     - description は 1-1024 文字
#     - license は必須で、空でない文字列(値と同梱 LICENSE の整合は lint-license.sh)
#     - frontmatter フィールドは許可リスト内のみ（仕様外は警告）
#   本体長:
#     - frontmatter を除いた SKILL.md 本文は 500 行以下
#       （gh skill publish の "recommended max: 500 for efficient context" 警告に合わせる）
set -eu

script_dir=$(cd -- "$(dirname "$0")" && pwd)

if ! command -v node >/dev/null 2>&1; then
  echo "lint-frontmatter.sh: Node.js が見つかりません" >&2
  exit 1
fi

exec node "$script_dir/lint-frontmatter.mjs"
