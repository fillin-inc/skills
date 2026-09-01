#!/bin/sh
# AGENTS.md のサイズが Codex の project_doc_max_bytes 既定値 (32 KiB) に
# 収まっているかを検証する。
#
# Codex は上限を超えた末尾を切り詰めるため、超過すると AGENTS.md 末尾の
# ルールがそのホストで読まれなくなる。Claude Code では読めても Codex では
# 読めないルールが発生するのを防ぐため lint に組み込む。
#
# しきい値:
#   - HARD_LIMIT: 32,768 bytes (Codex 既定)。超過は fail (exit 1)
#   - SOFT_LIMIT: 31,000 bytes (残 ~1.7 KiB)。超過は warn (exit 0)
#
# 使い方: sh ./bin/lint-agents-md-size.sh
#   AGENTS.md パスは第 1 引数で上書きできる (テスト用途):
#     sh ./bin/lint-agents-md-size.sh /path/to/AGENTS.md

set -eu

TARGET="${1:-AGENTS.md}"
HARD_LIMIT=32768
SOFT_LIMIT=31000

if [ ! -f "$TARGET" ]; then
    echo "lint-agents-md-size: SKIP ($TARGET が見つかりません)"
    exit 0
fi

SIZE=$(wc -c < "$TARGET" | tr -d ' ')

if [ "$SIZE" -gt "$HARD_LIMIT" ]; then
    OVER=$((SIZE - HARD_LIMIT))
    echo "lint-agents-md-size: FAIL" >&2
    echo "  $TARGET は ${SIZE} bytes で Codex 既定上限 ${HARD_LIMIT} bytes を ${OVER} bytes 超過しています。" >&2
    echo "  超過した末尾は Codex では切り詰められ読まれません。" >&2
    echo "  対応: 冗長節を docs/guidelines/ に分離するか、~/.codex/config.toml" >&2
    echo "  または対象リポジトリの .codex/config.toml のトップレベルに" >&2
    echo "    project_doc_max_bytes = 65536" >&2
    echo "  を設定して上限を引き上げてください (README 参照)。" >&2
    exit 1
fi

if [ "$SIZE" -gt "$SOFT_LIMIT" ]; then
    REMAIN=$((HARD_LIMIT - SIZE))
    echo "lint-agents-md-size: WARN"
    echo "  $TARGET は ${SIZE} bytes で Codex 上限まで残 ${REMAIN} bytes です。"
    echo "  追記時は docs/guidelines/ 分離を検討してください。"
    exit 0
fi

echo "lint-agents-md-size: PASS (${SIZE} bytes / ${HARD_LIMIT} bytes)"
