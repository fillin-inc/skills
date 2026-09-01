#!/bin/sh
# skills/**/*.md 内の同梱スクリプト呼び出しが、cwd 相対パス記法 (`./scripts/` /
# `scripts/`) ではなく skill ディレクトリ基準の絶対パス
# (`"$SKILL_DIR/scripts/..."`) で書かれていることを検証する。
#
# なぜ相対記法を禁止するか:
#   skill 起動時の cwd は「作業対象リポジトリ」であって skill ディレクトリでは
#   ない。md に `./scripts/xxx.sh` と書かれていると、エージェントはそれを成立
#   させるため skill ディレクトリへ `cd` する。すると cwd が作業対象リポジトリ
#   から外れ、repo を検査する preflight.sh 等が
#   "not inside a git repository" で落ちる。`cd` しない場合は単にファイル不在で
#   落ちる。
#
# 検出規則は 2 つ。対象は skills/**/*.md (SKILL.md / references/ /
# HOW_TO_USE.md / scripts/ 配下の md を含む。node_modules/ は除外):
#
#   規則 1: `./scripts/` が現れたら fail (出現位置を問わない)
#     先頭 `./` は実行を意図した書き方でしか出てこないため、散文中の言及でも
#     区別せず一律で fail にする。
#
#   規則 2: 先頭 `./` の無い `scripts/<name>.<ext>` が **コマンド起動位置** に
#     現れたら fail。コマンド起動位置は次の 3 通り (いずれも前置の
#     `timeout <N>` を許容):
#       (a) インタプリタ直後 — `sh` / `bash` / `node` / `python` / `python3` の
#           直後。行頭・空白・`(`・`` ` ``・`;`・`&`・`|` のいずれかに続くものだけ
#           をインタプリタと見なすので、`$(sh scripts/x.sh)` /
#           `eval "$(sh scripts/x.sh)"` も拾う
#       (b) インタプリタ省略かつ、実行文と断定できる文脈の直後 — `$(` /
#           サブシェル開始 `( ` / ` && ` / ` || ` / ` & ` / `;` / パイプ ` | ` /
#           制御構文キーワード (`if` `elif` `while` `until` `then` `else` `do`
#           `!`) / 行頭の環境変数代入前置。`OUT=$(scripts/foo.sh)` /
#           `a && scripts/next.sh` / `if scripts/foo.sh; then` /
#           `printf x | scripts/filter.sh` / `FOO=bar scripts/foo.sh` を拾う。
#           素の空白や backtick は文脈に含めない (散文中の言及と区別できなく
#           なるため)。パイプ文脈だけは markdown の表セル
#           (`| scripts/foo.sh |`) と衝突するため、行が `|` で始まらないことを
#           行頭から確認して切り分ける
#       (c) インタプリタ省略かつ行頭 (前置の空白を許容) で、直後が行末 /
#           **ASCII の可読文字** / コマンド区切り (`;` `&` `|` `)`) —
#           `scripts/preflight.sh --input-kind issue` /
#           `scripts/import.sh input.csv` / `scripts/foo.sh; echo done` を拾う
#
#     (c) で「直後が行末か ASCII 可読文字」を要求するのは、行頭から始まる日本語
#     散文 (`scripts/refresh-data.sh がこの出力と…`) を violation にしないため。
#     判定は LC_ALL=C 下のバイト比較で行い、マルチバイト文字 (0x80 以上) が続く
#     行を除外する。英文の散文が行頭から `scripts/foo.sh is …` と始まる場合は
#     誤検出になるが、skills 配下の md は日本語で書かれる前提なのでこの取り違えは
#     起きない。逆に、散文の途中に現れる言及 (`` `scripts/parse-args.sh` に委譲する ``)
#     やリポジトリ相対の手動実行手順 (`sh skills/<name>/scripts/setup.sh`) は
#     いずれの規則にも当たらず、意図的に検出しない。
#
# `cd` そのものは検出しない。相対記法を禁止すれば `cd` を誘発する原因が
# 消えるため、また skills 配下 md の `cd` は作業対象リポジトリ内での正当な用途
# (HOW_TO_USE の手動実行手順 / `cd "$REPO_ROOT"` 等) が大半で、例外規則を持つと
# 規則自体が形骸化するため。
#
# 使い方: sh ./bin/lint-script-invocation.sh [<skills-dir>]
#   <skills-dir> は既定でリポジトリの skills/。テストからの利用を想定して上書き可。
#
# exit code: 0 = 違反なし / 1 = 違反あり・実行エラー
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

SKILLS_DIR="${1:-$REPO_ROOT/skills}"

if [ ! -d "$SKILLS_DIR" ]; then
    echo "lint-script-invocation: skills ディレクトリが見つからない: $SKILLS_DIR" >&2
    exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lint-script-invocation.XXXXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM
FILELIST="$WORK_DIR/files"
FOUND="$WORK_DIR/found"
ERRLOG="$WORK_DIR/err"
: > "$FOUND"
: > "$ERRLOG"

# node_modules/ は skill が auto-install する外部パッケージの置き場 (gitignore 済み)。
# 同梱ドキュメントではないので走査対象から外す。
if ! find "$SKILLS_DIR" -type d -name node_modules -prune -o \
     -type f -name '*.md' -print > "$FILELIST"; then
    echo "lint-script-invocation: md ファイルの列挙に失敗した: $SKILLS_DIR" >&2
    exit 1
fi

# 相対呼び出しの検出パターン (スクリプト冒頭の規則 1 / 規則 2 に対応)。
SCRIPT_REF='scripts/[A-Za-z0-9._-]+\.(sh|bash|mjs|cjs|js|py)'
# インタプリタと見なす語の直前に許す文字 (行頭 / 空白 / `(` / backtick / `;` / `&` / `|`)。
CMD_HEAD='(^|[[:space:]]|[;&|(`])'
TIMEOUT_OPT='(timeout[[:space:]]+[0-9]+[[:space:]]+)?'
INTERPRETER="${TIMEOUT_OPT}(sh|bash|node|python3?)[[:space:]]+"
# インタプリタを省いた bare 記法を「実行文」と断定できる文脈。
# 素の `[[:space:]]` や backtick は入れない (散文中の言及と区別できなくなるため)。
#   - コマンド置換 / リスト演算子 (`&&` `||` `&`) / `;` / サブシェル開始 `( `
#   - シェルの制御構文キーワードと `!` 否定 (`if scripts/foo.sh; then` 等)
#   - 行頭の環境変数代入前置 (`FOO=bar scripts/foo.sh`)
BARE_CTX_SUBST='\$\(|\([[:space:]]+'
BARE_CTX_LISTOP='[[:space:]]+(&&|\|\||&)[[:space:]]+|;[[:space:]]*'
BARE_CTX_KEYWORD='(^|[[:space:]])(if|elif|while|until|then|else|do|!)[[:space:]]+'
BARE_CTX_ENVPREFIX='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+'
BARE_CTX="(${BARE_CTX_SUBST}|${BARE_CTX_LISTOP}|${BARE_CTX_KEYWORD}|${BARE_CTX_ENVPREFIX})"
# パイプ直後の bare 記法。markdown の表セル (`| scripts/foo.sh |`) と衝突するため、
# 行が `|` で始まらないこと (= 表の行ではないこと) を行頭から明示して切り分ける。
BARE_CTX_PIPE='^[[:space:]]*[^|[:space:]][^|]*\|[[:space:]]+'
# 行頭 bare 記法で「引数の始まり」と見なす文字。ASCII 可読文字 (0x21-0x7E) のみを許し、
# 日本語散文 (マルチバイト = 0x80 以上) を除外する。LC_ALL=C でバイト比較させる。
ARG_HEAD='[!-~]'
# 引数を伴わない行頭 bare 記法に直付けされうるコマンド区切り (`scripts/foo.sh; echo done`)。
CMD_SEP='[;&|)]'
PATTERN="\\./scripts/\
|${CMD_HEAD}${INTERPRETER}${SCRIPT_REF}\
|${BARE_CTX}${TIMEOUT_OPT}${SCRIPT_REF}\
|${BARE_CTX_PIPE}${TIMEOUT_OPT}${SCRIPT_REF}\
|^[[:space:]]*${TIMEOUT_OPT}${SCRIPT_REF}([[:space:]]*\$|[[:space:]]+${ARG_HEAD}|${CMD_SEP})"

# ファイルごとに grep して終了状態を個別に見る。
#   0    = 一致あり (違反)
#   1    = 一致なし
#   >= 2 = 読み取り失敗等の実行エラー
# xargs 経由だと「一致なし」も xargs の 123 に畳み込まれ、実行エラーと区別できない。
# /dev/null を第 2 引数に置くのは、単一ファイル指定でも grep にファイル名を
# 前置させるため。
COUNT=0
SEARCH_ERR=0
while IFS= read -r f; do
    COUNT=$((COUNT + 1))
    # `if grep ...; then` 形式だと fi 通過後の $? が 0 に戻り rc を取れないため、
    # `|| rc=$?` で直接捕捉する。
    rc=0
    LC_ALL=C grep -En -- "$PATTERN" "$f" /dev/null >> "$FOUND" 2>> "$ERRLOG" || rc=$?
    if [ "$rc" -ge 2 ]; then
        SEARCH_ERR=1
    fi
done < "$FILELIST"

if [ "$SEARCH_ERR" -ne 0 ] || [ -s "$ERRLOG" ]; then
    echo "lint-script-invocation: 走査中に実行エラーが発生した (検査結果は信頼できない)" >&2
    cat "$ERRLOG" >&2
    exit 1
fi

if [ ! -s "$FOUND" ]; then
    echo "lint-script-invocation: PASS ($COUNT files checked)"
    exit 0
fi

VIOLATIONS=$(wc -l < "$FOUND" | tr -d ' ')

echo "lint-script-invocation: FAIL ($VIOLATIONS 箇所)" >&2
echo "  skills 配下の md で同梱スクリプトを cwd 相対パス (./scripts/ または scripts/) で呼んでいます。" >&2
# $SKILL_DIR はエージェント向けの案内文として literal 出力する (展開させない)
# shellcheck disable=SC2016
echo '  skill ディレクトリ基準の絶対パス "$SKILL_DIR/scripts/<name>.sh" に書き換えてください。' >&2
# shellcheck disable=SC2016
echo '  $SKILL_DIR の宣言は bin/partials/skill-dir.md を SKILL.md 冒頭に埋め込みます。' >&2
echo "" >&2
sed "s|^$SKILLS_DIR/|skills/|" "$FOUND" >&2
exit 1
