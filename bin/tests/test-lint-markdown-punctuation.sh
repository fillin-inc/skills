#!/bin/bash
# bin/lint-markdown-punctuation.sh の検出 / 置換テスト。
# 各ケースは一時ファイルに markdown を書き、対象ファイルを明示指定して lint を実行する
# (リポジトリ全体の走査を巻き込まないため)。
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../lint-markdown-punctuation.sh"

pass=0
fail=0

assert_eq() {
    _name=$1
    _expected=$2
    _actual=$3
    if [ "$_expected" = "$_actual" ]; then
        printf '  PASS: %s\n' "$_name"
        pass=$((pass + 1))
    else
        printf '  FAIL: %s\n' "$_name"
        printf '    expected: %s\n' "$_expected"
        printf '    actual:   %s\n' "$_actual"
        fail=$((fail + 1))
    fi
}

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# コードフェンス / バッククォートは shellcheck からコマンド置換に見えるため変数経由で組み立てる
FENCE='```'
BT='`'

write_md() {
    _path="$TMPROOT/case.$$.$RANDOM.md"
    printf '%s\n' "$1" > "$_path"
    printf '%s' "$_path"
}

lint_status() {
    "$SCRIPT" "$1" >/dev/null 2>&1
    printf '%s' "$?"
}

echo "== 検出 (全角括弧は一律 violation = exit 1) =="

f=$(write_md 'IP アドレス（IPv4）を確認する。')
assert_eq "ASCII 混在は検出する" "1" "$(lint_status "$f")"

f=$(write_md '純日本語（補足）だけの括弧。')
assert_eq "日本語のみでも検出する" "1" "$(lint_status "$f")"

f=$(write_md '## 見出し（読者向け）')
assert_eq "見出し行でも検出する" "1" "$(lint_status "$f")"

f=$(write_md '- （行頭マーカー直後）も対象')
assert_eq "行頭リストマーカー直後も検出する" "1" "$(lint_status "$f")"

f=$(write_md '| 用途（説明） | 値 |')
assert_eq "表セル内も検出する" "1" "$(lint_status "$f")"

f=$(write_md '対応が取れない片側だけの全角（も検出する')
assert_eq "対応の取れない片側だけの全角も検出する" "1" "$(lint_status "$f")"

f=$(write_md '> **Note**: 注記ブロック（自作の Note は原文尊重の対象外）')
assert_eq "引用行も検出する (自作の Note ブロックのため)" "1" "$(lint_status "$f")"

printf '%ssh\necho "コメント内（説明）"\n%s\n' "$FENCE" "$FENCE" > "$TMPROOT/fence-sh.md"
assert_eq "sh フェンス内も検出する" "1" "$(lint_status "$TMPROOT/fence-sh.md")"

printf '%smarkdown\n| 本店（現在） | 値 |\n%s\n' "$FENCE" "$FENCE" > "$TMPROOT/fence-md.md"
assert_eq "markdown フェンス内も検出する (生成物テンプレート)" "1" "$(lint_status "$TMPROOT/fence-md.md")"

printf '%s\n図の注記（タグなしフェンス）\n%s\n' "$FENCE" "$FENCE" > "$TMPROOT/fence-notag.md"
assert_eq "タグなしフェンス内も検出する" "1" "$(lint_status "$TMPROOT/fence-notag.md")"

echo "== 非検出 (exit 0) =="

f=$(write_md '半角括弧 (IPv4) だけの行。')
assert_eq "半角のみは検出しない" "0" "$(lint_status "$f")"

f=$(write_md "${BT}インラインコード（IPv4）${BT} は原文保持。")
assert_eq "インラインコード内は検出しない" "0" "$(lint_status "$f")"

f=$(write_md "ルール説明の ${BT}（${BT} と ${BT}）${BT} も保持される。")
assert_eq "全角そのものを例示するインラインコードは検出しない" "0" "$(lint_status "$f")"

echo "== --fix による置換 =="

f=$(write_md 'IP アドレス（IPv4）を確認する。')
"$SCRIPT" --fix "$f" >/dev/null 2>&1
assert_eq "ASCII 混在を半角へ置換する" "IP アドレス(IPv4)を確認する。" "$(cat "$f")"

f=$(write_md '純日本語（補足）だけの括弧。')
"$SCRIPT" --fix "$f" >/dev/null 2>&1
assert_eq "日本語のみも半角へ置換する" "純日本語(補足)だけの括弧。" "$(cat "$f")"

f=$(write_md '> **Note**: 注記（補足）')
"$SCRIPT" --fix "$f" >/dev/null 2>&1
assert_eq "引用行も半角へ置換する" '> **Note**: 注記(補足)' "$(cat "$f")"

printf '%ssh\ngit grep -n "a.*\\(File\\|md\\)" # 文脈判断（残存がないこと）\n%s\n' "$FENCE" "$FENCE" > "$TMPROOT/fence-re.md"
"$SCRIPT" --fix "$TMPROOT/fence-re.md" >/dev/null 2>&1
assert_eq "フェンス内のコメントは置換し正規表現エスケープは保つ" \
    'git grep -n "a.*\(File\|md\)" # 文脈判断(残存がないこと)' "$(sed -n '2p' "$TMPROOT/fence-re.md")"

f=$(write_md "${BT}コード（保持）${BT} と 本文（置換）")
"$SCRIPT" --fix "$f" >/dev/null 2>&1
assert_eq "同一行のインラインコードだけ保持し本文は置換する" \
    "${BT}コード（保持）${BT} と 本文(置換)" "$(cat "$f")"

printf '1 行目（IPv4）\n2 行目（IPv6）\n' > "$TMPROOT/multi.md"
"$SCRIPT" --fix "$TMPROOT/multi.md" >/dev/null 2>&1
assert_eq "同一ファイル内の複数行を置換する" "1 行目(IPv4)
2 行目(IPv6)" "$(cat "$TMPROOT/multi.md")"

echo "== 入れ子 / 対応の取れない括弧 =="

printf '注記（対象は「シリーズ B（第 2 回）」で吸収される）\n' > "$TMPROOT/nested.md"
"$SCRIPT" --fix "$TMPROOT/nested.md" >/dev/null 2>&1
assert_eq "入れ子は内側・外側とも半角化する" \
    "注記(対象は「シリーズ B(第 2 回)」で吸収される)" "$(cat "$TMPROOT/nested.md")"

printf '開きだけ（の行\n閉じだけ）の行\n' > "$TMPROOT/unbalanced.md"
"$SCRIPT" --fix "$TMPROOT/unbalanced.md" >/dev/null 2>&1
assert_eq "複数行にまたがる括弧も各行で置換される" "開きだけ(の行
閉じだけ)の行" "$(cat "$TMPROOT/unbalanced.md")"

echo "== 置換後は lint を通過する =="
assert_eq "--fix 後は PASS になる" "0" "$(lint_status "$TMPROOT/multi.md")"
assert_eq "入れ子ケースも --fix 後は PASS" "0" "$(lint_status "$TMPROOT/nested.md")"

printf '\n結果: PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
