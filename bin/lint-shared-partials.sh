#!/bin/sh
# 共通 partial 文言のマニフェスト (bin/shared-partials.tsv) に基づき、
# 各 SKILL.md の partial マーカー間内容が SSOT partial と byte 同一かを検証する。
#
# 前提:
#   - partial ファイル (bin/partials/*.md) は先頭に
#     `<!-- @partial:<id> start -->` を、末尾に
#     `<!-- @partial:<id> end -->` を含む。partial ファイル全体を
#     SSOT テキストとして扱う (マーカー行含む)。
#   - TARGET_SKILL_MD 側は当該マーカー行 (含む) の間に、partial ファイル
#     全体と同じ内容 (マーカー行含む) が挿入されている必要がある。
#
# 使い方: sh ./bin/lint-shared-partials.sh
#   マニフェストは第 1 引数で上書きできる (テストからの利用を想定):
#     sh ./bin/lint-shared-partials.sh /path/to/manifest.tsv
#
# 実体は lint-shared-partials.mjs(1 プロセスで全 embedding を検査する)。
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

if ! command -v node >/dev/null 2>&1; then
  echo "lint-shared-partials: node が見つかりません。Node.js 22 以上をインストールしてください" >&2
  exit 1
fi

exec node "$HERE/lint-shared-partials.mjs" "$@"
