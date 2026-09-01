#!/bin/sh
# Markdown 括弧の全角/半角ルール (ASCII 混在時は半角) を検証する。
#
# 検出ロジックは bin/lint-markdown-punctuation.mjs に置いている。
# シェル (awk/sed) はマルチバイト文字境界の扱いが処理系依存で、macOS の
# BWK awk では全角括弧の substr が壊れるため、UTF-8 を正しく扱える
# Node.js に判定を委譲している。
#
# 検査対象: skills/ 配下と docs/ 配下の *.md、および AGENTS.md / README.md
#           (node_modules 配下は除外)
#
# 使い方:
#   sh ./bin/lint-markdown-punctuation.sh          # 検証のみ
#   sh ./bin/lint-markdown-punctuation.sh --fix    # 違反箇所を半角へ一括置換
#   sh ./bin/lint-markdown-punctuation.sh a.md b.md  # 対象を明示 (テスト用途)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

if ! command -v node >/dev/null 2>&1; then
    echo "lint-markdown-punctuation: FAIL" >&2
    echo "  node が見つかりません。本 lint は UTF-8 の文字境界を正しく扱うため Node.js を使用します。" >&2
    echo "  Node.js をインストールするか、asdf 等でバージョンを有効化してください。" >&2
    exit 1
fi

cd "$REPO_ROOT"

FIX=""
for arg in "$@"; do
    if [ "$arg" = "--fix" ]; then
        FIX="--fix"
    fi
done

# --fix 以外の位置引数が渡されていればそれを検査対象にする
EXPLICIT_TARGETS=0
for arg in "$@"; do
    if [ "$arg" != "--fix" ]; then
        EXPLICIT_TARGETS=1
    fi
done

if [ "$EXPLICIT_TARGETS" -eq 1 ]; then
    node "$REPO_ROOT/bin/lint-markdown-punctuation.mjs" "$@"
    exit $?
fi

TARGETS=$(mktemp)
trap 'rm -f "$TARGETS"' EXIT

find skills docs -name '*.md' -type f -not -path '*/node_modules/*' > "$TARGETS"
for f in AGENTS.md README.md; do
    [ -f "$f" ] && echo "$f" >> "$TARGETS"
done

if [ ! -s "$TARGETS" ]; then
    echo "lint-markdown-punctuation: SKIP (検査対象の markdown が見つかりません)"
    exit 0
fi

# shellcheck disable=SC2046 # ファイル名に空白を含まない前提で単語分割を利用する
if [ -n "$FIX" ]; then
    node "$REPO_ROOT/bin/lint-markdown-punctuation.mjs" --fix $(cat "$TARGETS")
else
    node "$REPO_ROOT/bin/lint-markdown-punctuation.mjs" $(cat "$TARGETS")
fi
