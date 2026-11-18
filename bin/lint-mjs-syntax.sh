#!/bin/sh
# skills/ と bin/ 配下の Node.js script(*.mjs / *.js)を `node --check` で構文検証する。
#
# ShellCheck が sh を検査するのに対応し、Node.js script の構文エラーを CI で検知する。
# 実行時エラーや型の誤りは対象外で、各 script のテストで検知する。
# 除外: node_modules/ と fixtures/ 配下
#
# 使い方: sh ./bin/lint-mjs-syntax.sh [<repo-root>]

set -eu

ROOT="${1:-.}"

if ! command -v node >/dev/null 2>&1; then
    echo "lint-mjs-syntax: node が見つかりません。Node.js 22 以上をインストールしてください" >&2
    exit 1
fi

cd "$ROOT"

dirs=""
for d in skills bin; do
    [ -d "$d" ] && dirs="$dirs $d"
done
if [ -z "$dirs" ]; then
    echo "lint-mjs-syntax: PASS (skills/ と bin/ なし)"
    exit 0
fi

# shellcheck disable=SC2086
found=$(find $dirs -type f \( -name '*.mjs' -o -name '*.js' \) \
    -not -path '*/node_modules/*' -not -path '*/fixtures/*' | sort)

count=$(printf '%s\n' "$found" | grep -c . || true)

# node --check は 1 ファイルずつしか検査できないため、並列に起動して待ち時間を縮める。
# 失敗したファイルは一時ディレクトリに診断を残し、最後にまとめて表示する。
errdir=$(mktemp -d "${TMPDIR:-/tmp}/lint-mjs-syntax.XXXXXXXX")
trap 'rm -rf "$errdir"' EXIT
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
export errdir
# shellcheck disable=SC2016  # sh -c の本体。子 shell 側で展開させる
printf '%s\n' "$found" | grep . | tr '\n' '\0' |
    xargs -0 -n 1 -P "$jobs" sh -c '
        f=$1
        if ! out=$(node --check "$f" 2>&1); then
            id=$(printf "%s" "$f" | cksum | cut -d" " -f1)
            printf "lint-mjs-syntax: %s に構文エラーがあります\n%s\n" "$f" "$out" > "$errdir/$id.err"
        fi
    ' _

bad=0
for e in "$errdir"/*.err; do
    [ -f "$e" ] || continue
    bad=$((bad + 1))
    cat "$e" >&2
done

if [ "$bad" -gt 0 ]; then
    echo "lint-mjs-syntax: FAIL ($bad / $count files)" >&2
    exit 1
fi
echo "lint-mjs-syntax: PASS ($count files checked)"
