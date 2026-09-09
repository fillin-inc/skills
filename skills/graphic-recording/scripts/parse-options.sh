#!/bin/sh
# グラフィックレコーディング画像生成のオプションを解決し、
# 呼び出し側 (ホストエージェント) が読む形で標準出力へ書き出す。
#
# 出力形式:
#   KEY=VALUE 行のブロック
#   --- STYLE --- 以降にトーン別のスタイル指示 (複数行)
#   --- LAYOUT --- 以降に向き別のレイアウト指示 (複数行)
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

echo '--- STYLE ---'
case "$tone" in
  business)
    cat <<'STYLE'
配色: 白またはごく淡いグレーの地に、ネイビーとグレーを基調とし、アクセントは 1 色だけ使う。彩度は全体的に低く保つ。
線: 定規で引いたような直線と小さめの角丸で構成する。手描き感は最小限に留める。
文字: 端正なゴシック体。見出しは太字、本文は細字。装飾文字や飾り罫を使わない。
要素: 矩形のカード、番号付きのステップ、細めの矢印、単色の線画アイコン。
避ける: キャラクター、絵文字調のイラスト、派手なグラデーション、多用された吹き出し。
STYLE
    ;;
  standard)
    cat <<'STYLE'
配色: 白またはクリーム色の紙地に、青・緑・橙・赤・黒の 5 色マーカーで描く。
線: 太めのマーカーで引いた手描き風の線。わずかな揺れと強弱がある。
文字: 手書き風のゴシック。見出しは囲み文字またはリボン状のバナーに載せる。
要素: 付箋、吹き出し、太い矢印、簡略化された人型アイコン、電球や星などの記号。
避ける: 写真調の質感、細かすぎる装飾、判読を妨げる重なり。
STYLE
    ;;
  pop)
    cat <<'STYLE'
配色: ビビッドな黄・ピンク・水色・黄緑を含む 5〜6 色。背景に淡いドットやストライプを敷く。
線: 太く勢いのある手描き線。強調には二重線や集中線を使う。
文字: 大きく躍動的な手書き文字。見出しは吹き出しやバースト形に載せる。
要素: デフォルメされた人物、丸みのあるアイコン、リボン、きらめき、大きな矢印。
避ける: 情報が読めなくなるほどの装飾過多、暗く沈んだ配色。
STYLE
    ;;
  mono)
    cat <<'STYLE'
配色: 白地に黒 1 色。濃淡はハッチング・網掛け・線の太さで表し、中間調のグレー塗りに頼らない。
線: 均一な太さの手描き線。強調は二重線と太枠で行う。
文字: 判読性の高い手書き風ゴシック。見出しは太枠または白抜き文字にする。
要素: 線画アイコン、白地の付箋、塗りつぶした三角の矢印。
避ける: 薄いグレーの塗り分けだけによる区別、細すぎる罫線。白黒コピーで潰れないよう隣接要素のコントラスト差を大きく取る。
STYLE
    ;;
esac

echo '--- LAYOUT ---'
case "$orientation" in
  landscape)
    cat <<'LAYOUT'
上部: 横長のタイトル帯を置く。左にタイトル、右に日付や出典などの補足を小さく添える。
中央: 3〜4 列のゾーンに分け、1 ゾーンにつき 1 ブロックを配置する。視線は左から右へ流す。
下部: 結論またはネクストアクションの帯を横一杯に置く。
関係: ゾーン間は矢印でつなぎ、順序・因果・対比のいずれであるかが一目で分かるようにする。
余白: 上下左右に均等な余白を取り、要素を紙端まで詰めない。
LAYOUT
    ;;
  portrait)
    cat <<'LAYOUT'
上部: タイトル帯を置く。タイトルの下に 1 行のサマリーを添える。
中央: 3〜6 段に区切り、1 段につき 1 ブロックを配置する。段ごとに要素を左右へ振り分け、視線をジグザグに導く。
下部: 結論またはネクストアクションの帯を横一杯に置く。
関係: 段の間は下向きの矢印でつなぎ、対比する内容は同じ段に左右で並べる。
余白: 上下左右に均等な余白を取り、要素を紙端まで詰めない。
LAYOUT
    ;;
esac
