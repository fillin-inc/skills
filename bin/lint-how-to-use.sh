#!/bin/sh
# skills/<name>/HOW_TO_USE.md に記載されたフラグ集合と、skill が実際に受け付ける
# フラグ集合の乖離 (drift) を機械検証する。
#
# HOW_TO_USE.md は SKILL.md / scripts/ の引数解析を SSOT とする派生ドキュメント。
# SSOT 側だけ変えて派生側の更新を忘れる事故を make lint / CI で検出する。
#
# 使い方: sh ./bin/lint-how-to-use.sh [<skills-dir>]
#   <skills-dir> は既定でリポジトリの skills/。テストからの利用を想定して上書き可。
#
# 抽出方法 (skill が受け付けるフラグ = 期待値):
#   A. 共通 parse-flags.sh の spec DSL (<name>:bool / <name>:value)
#      - 走査対象: skills/<name>/scripts/*.sh と skills/<name>/SKILL.md の双方
#        (SKILL.md に spec DSL を直接書く skill があるため両方を見る)
#      - PF_SPECS="..." のような変数間接と、行末 `\` の行継続を解決する
#      - .sh のコメント行は走査しない (説明用の記述が実体と drift しうるため)
#   B. 自前 case 実装の literal
#      - 走査対象: skills/<name>/scripts/parse-*.sh
#      - case のパターン位置 (行頭から最初の `)` まで) に現れる --flag のみを採る
#      - `--flag | --flag=*)` のように `|` 前後にスペースが入る形も拾う
#      case literal を scripts/*.sh 全体へ広げると内部スクリプトの引数
#      (--input-kind / --phase-3a-file 等) が大量に混入して誤検出が倍増するため、
#      ユーザー入力の解析口である parse-*.sh 命名に限定している。
#   除外するスクリプト:
#      - parse-flags.sh: DSL の spec を受け取る側であり skill のフラグを持たない
#      - reference-context.sh: skill が --pr / --issue 等をプログラム的に渡す
#        内部ヘルパで、ユーザーが指定する起動フラグの定義元ではない
#
# 抽出方法 (HOW_TO_USE.md に記載されたフラグ = 実際値):
#   オプション節 (見出しに フラグ / オプション / 引数 / option / flag を含む節) の
#   本文に限り、表の 1 列目とリスト項目から --flag を拾う。
#   ファイル全体から拾うと他 skill のフラグ言及・typo 例・ダミー例を誤検出するため。
#   除外する節:
#     - 「オプション組み合わせ別の特殊用法」のような用例節 (見出しに 組み合わせ)
#     - skill の起動フラグでない同梱スクリプト固有の節 (見出しに scripts/ や .sh)
#     - オプション節の下位節でも、見出し自身がオプション節でないもの (解説とみなす)
#   表の 2 列目以降 (説明文) は他コマンドのフラグが現れるため見ない。
#
# --help は POSIX 慣例のフラグで HOW_TO_USE への記載を必須としないため、
# 両側から一律に除外する。
#
# 個別事情は HOW_TO_USE.md に次の行コメントを置くことで除外できる:
#   <!-- lint-how-to-use: ignore --xxx -->
#
# exit code: 0 = drift なし / 1 = drift あり・実行エラー
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

SKILLS_DIR="${1:-$REPO_ROOT/skills}"

if [ ! -d "$SKILLS_DIR" ]; then
    echo "lint-how-to-use: skills ディレクトリが見つからない: $SKILLS_DIR" >&2
    exit 1
fi
# 後段で REPO_ROOT へ cd するため、相対パス指定でも壊れないよう絶対パス化する
SKILLS_DIR=$(cd "$SKILLS_DIR" && pwd)

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lint-how-to-use.XXXXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

# ---- awk プログラム -------------------------------------------------------

# A. parse-flags.sh の spec DSL 抽出。
#    MODE=sh のときのみコメント行スキップと変数代入の収集を行う。
# shellcheck disable=SC2016  # awk プログラム本体。シェル展開させない
AWK_SPEC='
function emit_spec(tok,   name) {
    if (tok ~ /^[a-z][a-z0-9-]*:(bool|value)$/) {
        name = tok
        sub(/:.*$/, "", name)
        print "--" name
    }
}
function process(line,   idx, rest, n, toks, i, t, vn, m, vt, j) {
    idx = index(line, MARK)
    if (idx == 0) return
    rest = substr(line, idx + length(MARK))
    n = split(rest, toks, /[ \t]+/)
    for (i = 1; i <= n; i++) {
        t = toks[i]
        gsub(/^[")(`]+/, "", t)
        gsub(/[")(`]+$/, "", t)
        if (t == "--") return
        if (t ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) {
            vn = t
            sub(/^\$\{?/, "", vn)
            sub(/\}$/, "", vn)
            if (vn in VARS) {
                m = split(VARS[vn], vt, /[ \t]+/)
                for (j = 1; j <= m; j++) emit_spec(vt[j])
            }
            continue
        }
        emit_spec(t)
    }
}
{
    lines[NR] = $0
    if (MODE == "sh" && $0 ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*="[^"]*"/) {
        eqpos = index($0, "=")
        vname = substr($0, 1, eqpos - 1)
        sub(/^[ \t]+/, "", vname)
        vval = substr($0, eqpos + 2)
        qpos = index(vval, "\"")
        VARS[vname] = substr(vval, 1, qpos - 1)
    }
}
END {
    buf = ""
    for (i = 1; i <= NR; i++) {
        line = lines[i]
        if (MODE == "sh" && line ~ /^[ \t]*#/) { buf = ""; continue }
        if (buf != "") line = buf " " line
        buf = ""
        if (line ~ /\\$/) {
            sub(/\\$/, "", line)
            buf = line
            continue
        }
        process(line)
    }
    if (buf != "") process(buf)
}
'

# B. 自前 case 実装の literal 抽出。
# shellcheck disable=SC2016  # awk プログラム本体。シェル展開させない
AWK_CASE='
{
    line = $0
    if (line ~ /^[ \t]*#/) next
    p = index(line, ")")
    if (p == 0) next
    pat = substr(line, 1, p - 1)
    if (pat !~ /--[a-z]/) next
    # case のパターンに使われない文字が混ざる行 (echo 等) は対象外。
    # 文字列 regex にしているのは、bracket 内の `/` の扱いが awk 実装で揺れるため。
    if (pat ~ "[^-A-Za-z0-9_=*|./ \t]") next
    while (match(pat, /--[a-z][a-z0-9-]*/)) {
        print substr(pat, RSTART, RLENGTH)
        pat = substr(pat, RSTART + RLENGTH)
    }
}
'

# C. HOW_TO_USE.md のオプション節からの抽出。
# shellcheck disable=SC2016  # awk プログラム本体。シェル展開させない
AWK_HTU='
function is_option_heading(t) {
    if (index(t, "組み合わせ") > 0) return 0
    if (index(t, "scripts/") > 0) return 0
    if (index(t, ".sh") > 0) return 0
    if (index(t, "フラグ") > 0) return 1
    if (index(t, "オプション") > 0) return 1
    if (index(t, "引数") > 0) return 1
    if (t ~ /[Oo]ption/) return 1
    if (t ~ /[Ff]lag/) return 1
    return 0
}
BEGIN { fence = 0; insec = 0 }
{
    line = $0
    if (line ~ /^[ \t]*```/) { fence = 1 - fence; next }
    if (fence) next
    if (line ~ /^#+[ \t]/) {
        h = line
        sub(/^[ \t]*/, "", h)
        n = 0
        while (substr(h, n + 1, 1) == "#") n++
        text = substr(h, n + 1)
        # 見出しが来た時点で節は閉じる。オプション節の下位節であっても
        # 見出し自身がオプション節でなければ本文は解説とみなし拾わない。
        insec = is_option_heading(text)
        next
    }
    if (!insec) next
    if (line ~ /^[ \t]*>/) next
    s = ""
    if (line ~ /^[ \t]*\|/) {
        # 表は 1 列目 (フラグ名の列) だけを見る。2 列目以降の説明文には
        # 他コマンドのフラグ (例: gh pr create --reviewer) が現れるため。
        c = line
        sub(/^[ \t]*\|/, "", c)
        e = index(c, "|")
        if (e == 0) next
        s = substr(c, 1, e - 1)
    } else if (line ~ /^[ \t]*[-*+][ \t]/ || line ~ /^[ \t]*[0-9]+\.[ \t]/) {
        s = line
    } else {
        next
    }
    while (match(s, /--[a-z][a-z0-9-]*/)) {
        print substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
    }
}
'

# ---- 抽出ヘルパ -----------------------------------------------------------

# skill が受け付けるフラグを stdout に 1 行 1 件で出力する
extract_expected() {
    _dir=$1
    if [ -f "$_dir/SKILL.md" ]; then
        awk -v MARK="parse-flags.sh" -v MODE="md" "$AWK_SPEC" "$_dir/SKILL.md"
    fi
    # A: spec DSL は scripts/*.sh 全体を走査する (parse-*.sh 以外の名前で
    #    ユーザー入力を解析する skill を取りこぼさないため)。ただし共通
    #    parse-flags.sh 自身と、skill がプログラム的に引数を渡す内部ヘルパは除く。
    for _f in "$_dir"/scripts/*.sh; do
        [ -f "$_f" ] || continue
        case "$(basename "$_f")" in
            parse-flags.sh | reference-context.sh) continue ;;
        esac
        awk -v MARK="parse-flags.sh" -v MODE="sh" "$AWK_SPEC" "$_f"
    done
    # B: case literal は parse-*.sh に限定する (内部スクリプトの引数が混入する)
    for _f in "$_dir"/scripts/parse-*.sh; do
        [ -f "$_f" ] || continue
        case "$(basename "$_f")" in
            parse-flags.sh) continue ;;
        esac
        awk "$AWK_CASE" "$_f"
    done
}

# HOW_TO_USE.md に記載されたフラグを stdout に 1 行 1 件で出力する
extract_documented() {
    awk "$AWK_HTU" "$1"
}

normalize() {
    grep -v -x -- '--help' | LC_ALL=C sort -u
}

join_flags() {
    tr '\n' ' ' | sed 's/ *$//'
}

# ---- メインループ ---------------------------------------------------------

cd "$REPO_ROOT"

fail=0
checked=0
skipped=0

for skill_dir in "$SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill=$(basename "$skill_dir")
    htu="$skill_dir/HOW_TO_USE.md"

    if [ ! -f "$htu" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    extract_expected "$skill_dir" | normalize > "$WORK_DIR/expected"
    extract_documented "$htu" | normalize > "$WORK_DIR/documented"

    # 行単位の無視コメントを両側から落とす
    sed -n 's/.*lint-how-to-use:[[:space:]]*ignore[[:space:]]*\(--[a-z][a-z0-9-]*\).*/\1/p' \
        "$htu" | LC_ALL=C sort -u > "$WORK_DIR/ignored"
    if [ -s "$WORK_DIR/ignored" ]; then
        LC_ALL=C comm -23 "$WORK_DIR/expected" "$WORK_DIR/ignored" > "$WORK_DIR/expected.tmp"
        mv "$WORK_DIR/expected.tmp" "$WORK_DIR/expected"
        LC_ALL=C comm -23 "$WORK_DIR/documented" "$WORK_DIR/ignored" > "$WORK_DIR/documented.tmp"
        mv "$WORK_DIR/documented.tmp" "$WORK_DIR/documented"
    fi

    if [ ! -s "$WORK_DIR/expected" ] && [ ! -s "$WORK_DIR/documented" ]; then
        # フラグを持たない skill。検査対象なし
        skipped=$((skipped + 1))
        continue
    fi

    checked=$((checked + 1))

    missing=$(LC_ALL=C comm -23 "$WORK_DIR/expected" "$WORK_DIR/documented" | join_flags)
    stale=$(LC_ALL=C comm -13 "$WORK_DIR/expected" "$WORK_DIR/documented" | join_flags)

    if [ -n "$missing" ] || [ -n "$stale" ]; then
        echo "lint-how-to-use: drift 検出: $skill" >&2
        if [ -n "$missing" ]; then
            echo "  未ドキュメント (scripts にあり HOW_TO_USE に無い): $missing" >&2
        fi
        if [ -n "$stale" ]; then
            echo "  記載残り (HOW_TO_USE にあり scripts に無い): $stale" >&2
        fi
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "lint-how-to-use: FAIL" >&2
    exit 1
fi

echo "lint-how-to-use: PASS ($checked skills checked, $skipped skipped)"
