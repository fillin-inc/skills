#!/bin/sh
# template-fill のオプションを解決し、呼び出し側 (ホストエージェント) が読む
# KEY=VALUE 形式で標準出力へ書き出す。
#
# 終了コード:
#   0  正常
#   64 引数エラー (usage)
#   66 テンプレートが見つからない / 読めない
set -eu

usage() {
  cat >&2 <<'USAGE'
usage: parse-options.sh <template.md> [--output <path>]
USAGE
}

die() {
  printf 'parse-options.sh: %s\n' "$1" >&2
  usage
  exit 64
}

template=""
output=""

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || die "--output に値がありません"
      output="$2"
      shift 2
      ;;
    --output=*)
      output="${1#--output=}"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --*)
      die "未知のオプション: $1"
      ;;
    *)
      [ -z "$template" ] || die "テンプレートは 1 つだけ指定できます: $1"
      template="$1"
      shift
      ;;
  esac
done

[ -n "$template" ] || die "テンプレートを指定してください"

lower=$(printf '%s' "$template" | tr '[:upper:]' '[:lower:]')
case "$lower" in
  *.md | *.markdown) ;;
  *) die "テンプレートは Markdown (.md / .markdown) のみ対応しています: $template" ;;
esac

if [ ! -f "$template" ] || [ ! -r "$template" ]; then
  printf 'parse-options.sh: テンプレートが見つからないか読めません: %s\n' "$template" >&2
  exit 66
fi

if [ -n "$output" ]; then
  [ ! -e "$output" ] || die "出力先が既に存在します (上書きしません): $output"
else
  # テンプレート名 + 当日の日付で作業ディレクトリに置く。既存ファイルは上書きしない。
  stem=$(basename "$template")
  base="${stem%.*}-$(date +%Y-%m-%d)"
  output="$base.md"
  n=2
  while [ -e "$output" ]; do
    output="$base-$n.md"
    n=$((n + 1))
  done
fi

printf 'TEMPLATE=%s\n' "$template"
printf 'OUTPUT_PATH=%s\n' "$output"
