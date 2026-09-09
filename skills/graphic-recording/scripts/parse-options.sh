#!/bin/sh
# グラフィックレコーディング画像生成のオプションを解決し、
# 呼び出し側 (ホストエージェント) が読む形で標準出力へ書き出す。
#
# 出力形式:
#   KEY=VALUE 行のブロック。画風とレイアウトの本文は references/presets.md が
#   持ち、本スクリプトはどの節を読むかを指す見出し名だけを出す。
#
# 終了コード:
#   0  正常
#   64 引数エラー (usage)
set -eu

usage() {
  cat >&2 <<'USAGE'
usage: parse-options.sh [--tone business|standard|pop|mono]
                          [--orientation landscape|portrait]
                          [--output <path>]
                          [<入力テキストまたはファイルパス> ...]
USAGE
}

die() {
  printf 'parse-options.sh: %s\n' "$1" >&2
  usage
  exit 64
}

tone=standard
orientation=landscape
output=""
input_files=""
input_text=""

while [ $# -gt 0 ]; do
  case "$1" in
    --tone)
      [ $# -ge 2 ] || die "--tone に値がありません"
      tone="$2"
      shift 2
      ;;
    --tone=*)
      tone="${1#--tone=}"
      shift
      ;;
    --orientation)
      [ $# -ge 2 ] || die "--orientation に値がありません"
      orientation="$2"
      shift 2
      ;;
    --orientation=*)
      orientation="${1#--orientation=}"
      shift
      ;;
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
      # 既存ファイルを指すなら入力ファイル、そうでなければ入力テキストとして扱う。
      if [ -f "$1" ]; then
        input_files="${input_files:+$input_files }$1"
      else
        input_text="${input_text:+$input_text }$1"
      fi
      shift
      ;;
  esac
done

case "$tone" in
  business | standard | pop | mono) ;;
  *) die "--tone は business / standard / pop / mono のいずれかです: $tone" ;;
esac

case "$orientation" in
  landscape)
    aspect_exact="1.414:1"
    aspect_fallback="4:3"
    aspect_fallback_alt="3:2"
    pixel_width=1754
    pixel_height=1240
    ;;
  portrait)
    aspect_exact="1:1.414"
    aspect_fallback="3:4"
    aspect_fallback_alt="2:3"
    pixel_width=1240
    pixel_height=1754
    ;;
  *)
    die "--orientation は landscape / portrait のいずれかです: $orientation"
    ;;
esac

printf 'TONE=%s\n' "$tone"
printf 'ORIENTATION=%s\n' "$orientation"
printf 'ASPECT_EXACT=%s\n' "$aspect_exact"
printf 'ASPECT_FALLBACK=%s\n' "$aspect_fallback"
printf 'ASPECT_FALLBACK_ALT=%s\n' "$aspect_fallback_alt"
printf 'PIXEL_WIDTH=%s\n' "$pixel_width"
printf 'PIXEL_HEIGHT=%s\n' "$pixel_height"
printf 'OUTPUT_PATH=%s\n' "$output"
printf 'INPUT_FILES=%s\n' "$input_files"
printf 'INPUT_TEXT=%s\n' "$input_text"
printf 'STYLE_SECTION=## トーン: %s\n' "$tone"
printf 'LAYOUT_SECTION=## 向き: %s\n' "$orientation"
