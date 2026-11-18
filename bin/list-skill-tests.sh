#!/bin/sh
# make test が実行する skill 同梱テストを列挙する(SSOT)。
#
# 対象(skill ディレクトリ直下の scripts/ 基準。skill ディレクトリは skills/<name>/ か
# skills/<group>/<name>/ で、SKILL.md を持つもの):
#   - <skill>/scripts/tests/test-*.sh   → bash で実行
#   - <skill>/scripts/tests/test-*.mjs  → node で実行
#   - <skill>/scripts/tests/*.test.mjs  → node --test で実行
#   - <skill>/scripts/*.test.mjs        → node --test で実行
#
# bin/lint-skill-tests.sh はこの一覧の外に置かれたテストファイルを error にする。
# 配置規則を変えるときは本スクリプトだけを直す。
#
# 使い方: sh ./bin/list-skill-tests.sh [<repo-root>]
#   stdout にリポジトリルート相対パスを 1 行 1 件、辞書順で出す。

set -eu

ROOT="${1:-.}"

cd "$ROOT"
for d in skills/*/SKILL.md skills/*/*/SKILL.md; do
    [ -f "$d" ] || continue
    d=${d%/SKILL.md}
    # SKILL.md を持つ skill の下は group ではない(skill 内のテンプレート等の SKILL.md を skill とみなさない)
    case "$d" in skills/*/*) [ -f "${d%/*}/SKILL.md" ] && continue ;; esac
    for f in \
        "$d"/scripts/tests/test-*.sh \
        "$d"/scripts/tests/test-*.mjs \
        "$d"/scripts/tests/*.test.mjs \
        "$d"/scripts/*.test.mjs; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
done | sort -u
