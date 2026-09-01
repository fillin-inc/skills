#!/bin/bash
# bin/lint-how-to-use.sh のユニットテスト。
# 実リポジトリの skills/ には依存せず、mktemp -d で作った隔離 sandbox に
# 疑似 skill ディレクトリを組み立てて各検出パターンを検証する。
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
SCRIPT="$REPO_ROOT/bin/lint-how-to-use.sh"

pass=0
fail=0
SANDBOXES=()

cleanup() {
    # bash 3.2 (macOS 既定) は空配列 + set -u で "${arr[@]}" が unbound variable に
    # なる既知バグがあるため、要素数チェックで guard する。
    if [ "${#SANDBOXES[@]}" -gt 0 ]; then
        for d in "${SANDBOXES[@]}"; do
            [ -d "$d" ] && rm -rf "$d"
        done
    fi
}
trap cleanup EXIT

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

assert_contains() {
    _name=$1
    _needle=$2
    _haystack=$3
    if printf '%s' "$_haystack" | grep -qF -e "$_needle"; then
        printf '  PASS: %s\n' "$_name"
        pass=$((pass + 1))
    else
        printf '  FAIL: %s (期待する部分文字列が出力に含まれない: %s)\n' "$_name" "$_needle"
        printf '    actual: %s\n' "$_haystack"
        fail=$((fail + 1))
    fi
}

assert_not_contains() {
    _name=$1
    _needle=$2
    _haystack=$3
    if printf '%s' "$_haystack" | grep -qF -e "$_needle"; then
        printf '  FAIL: %s (含まれてはいけない部分文字列がある: %s)\n' "$_name" "$_needle"
        printf '    actual: %s\n' "$_haystack"
        fail=$((fail + 1))
    else
        printf '  PASS: %s\n' "$_name"
        pass=$((pass + 1))
    fi
}

# sandbox の skills/ パスを SANDBOX_SKILLS に格納する。
# command substitution で呼ぶと subshell 化して SANDBOXES への追記が
# 親シェルに残らず後始末できないため、戻り値ではなく変数で受け渡す。
new_sandbox() {
    _dir=$(mktemp -d)
    SANDBOXES+=("$_dir")
    mkdir -p "$_dir/skills"
    SANDBOX_SKILLS="$_dir/skills"
}

# 疑似 skill の scripts/ ディレクトリを用意する
new_skill() {
    _skills=$1
    _name=$2
    mkdir -p "$_skills/$_name/scripts"
    printf '%s\n' "$_skills/$_name"
}

# --- case 1: spec DSL (基本形) が一致すれば PASS ---
echo "case 1: parse-flags.sh の spec DSL と HOW_TO_USE が一致"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" alpha)
cat > "$S/scripts/parse-alpha-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool out:value -- "$INPUT") || exit 64
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# alpha 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |
| `--out <path>` | 出力先 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_contains "PASS 表示" "lint-how-to-use: PASS (1 skills checked" "$out"

# --- case 2: 変数間接 (PF_SPECS) を解決する ---
echo "case 2: PF_SPECS 経由の変数間接"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" bravo)
cat > "$S/scripts/parse-bravo-args.sh" <<'EOF'
#!/bin/sh
PF_SPECS="reviewer:value fix:bool auto:bool"
# shellcheck disable=SC2086
eval "$("$HERE/parse-flags.sh" $PF_SPECS -- "$input")"
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# bravo 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--reviewer <agent>` | reviewer 指定 |
| `--fix` | 修正モード |
| `--auto` | 無人完走 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_contains "PASS 表示" "lint-how-to-use: PASS (1 skills checked" "$out"

# --- case 3: 行継続 (行末 backslash) を結合する ---
echo "case 3: parse-flags.sh 呼び出しの行継続"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" charlie)
cat > "$S/scripts/parse-charlie-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" \
    auto:bool fix:bool base:value \
    -- "$INPUT") || exit 64
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# charlie 利用ガイド

## フラグ一覧

- `--auto`: 無人完走
- `--fix`: 修正モード
- `--base <branch>`: base ブランチ
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_contains "PASS 表示" "lint-how-to-use: PASS (1 skills checked" "$out"

# --- case 4: 自前 case 実装 (`|` 前後スペースあり) を拾う ---
echo "case 4: case パターンの literal 抽出"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" delta)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
case "$1" in
    --max-pages | --max-pages=*)
        shift
        ;;
    --clean)
        shift
        ;;
    -h | --help)
        exit 0
        ;;
esac
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# delta 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--max-pages <N>` | 最大ページ数 |
| `--clean` | キャッシュ削除 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0 (--help は両側から除外)" "0" "$rc"

# --- case 5: SKILL.md 側に spec DSL がある skill ---
echo "case 5: SKILL.md 側の spec DSL"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" echo-skill)
cat > "$S/SKILL.md" <<'EOF'
# echo-skill

```sh
if ! OUT=$(./scripts/parse-flags.sh auto:bool our-service:value out:value -- "$USER_INPUT"); then exit 1; fi
```
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# echo-skill 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |
| `--our-service <name>` | 自社サービス |
| `--out <path>` | 出力先 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"

# --- case 6: HOW_TO_USE からフラグが欠けていれば error ---
echo "case 6: 未ドキュメントのフラグを検出"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" foxtrot)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool session:bool -- "$INPUT") || exit 64
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# foxtrot 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 1" "1" "$rc"
assert_contains "skill 名を報告" "drift 検出: foxtrot" "$out"
assert_contains "未ドキュメントを報告" "未ドキュメント (scripts にあり HOW_TO_USE に無い): --session" "$out"

# --- case 7: scripts に無いフラグが HOW_TO_USE に残っていれば error ---
echo "case 7: 廃止済みフラグの記載残りを検出"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" golf)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool -- "$INPUT") || exit 64
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# golf 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |
| `--legacy` | 廃止済み |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 1" "1" "$rc"
assert_contains "記載残りを報告" "記載残り (HOW_TO_USE にあり scripts に無い): --legacy" "$out"

# --- case 8: HOW_TO_USE.md が無い skill は skip ---
echo "case 8: HOW_TO_USE.md 不在は skip"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" hotel)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool -- "$INPUT") || exit 64
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_contains "skip として集計" "0 skills checked, 1 skipped" "$out"

# --- case 9: フラグを持たない skill / parse-*.sh を持たない skill は skip ---
echo "case 9: フラグ無し skill は skip"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" india)
cat > "$S/scripts/collect.sh" <<'EOF'
#!/bin/sh
echo hello
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# india 利用ガイド

## フラグ

india はフラグを持ちません。
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_contains "skip として集計" "0 skills checked, 1 skipped" "$out"

# --- case 10: オプション節の外は拾わない (他 skill 言及 / typo 例 / ダミー) ---
echo "case 10: オプション節外の誤検出源を拾わない"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" juliet)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool -- "$INPUT") || exit 64
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# juliet 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走。下流の `cross-review --reviewer with-codex --fix` にも伝播する |

> 未知フラグ(`--audo` のような typo)は exit 64 で拒否されます。

`--foo` のようなダミーも同様に拒否されます。

## オプション組み合わせ別の特殊用法

```bash
juliet --auto
```

- `--legacy-example` は用例節なので拾われない

## scripts/juliet-cache.sh のオプション

| オプション | 機能 |
|---|---|
| `--refresh` | キャッシュ再取得 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_not_contains "誤検出なし" "drift 検出" "$out"

# --- case 11: 行単位の無視コメントで除外できる ---
echo "case 11: ignore コメントによる除外"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" kilo)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
case "$1" in
    --auto) shift ;;
    --children|--children=*)
        echo "--children は受け付けません" >&2
        exit 65
        ;;
esac
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# kilo 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |

<!-- lint-how-to-use: ignore --children : 拒否ハンドラであり受理フラグではない -->
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_not_contains "ignore 済みは報告しない" "--children" "$out"

# --- case 12: オプション節の下位節 (見出しが非オプション) は拾わない ---
echo "case 12: オプション節の非オプション下位節は拾わない"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" lima)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool -- "$INPUT") || exit 64
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# lima 利用ガイド

## 共通フラグ

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |

### `--auto` 時の subcommand 別具体挙動

| subcommand | `--auto` の挙動 |
|---|---|
| `run --deep` | 深掘りを skip |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0 (下位節の --deep は拾わない)" "0" "$rc"

# --- case 14: parse-*.sh 命名でないスクリプトの spec DSL も拾う ---
echo "case 14: parse-*.sh 以外の spec DSL"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" mike)
cat > "$S/scripts/args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool depth:value -- "$INPUT") || exit 64
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# mike 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 1" "1" "$rc"
assert_contains "parse-*.sh 以外も走査" "未ドキュメント (scripts にあり HOW_TO_USE に無い): --depth" "$out"

# --- case 15: reference-context.sh は内部ヘルパとして除外する ---
echo "case 15: reference-context.sh の除外"
new_sandbox
SKILLS="$SANDBOX_SKILLS"
S=$(new_skill "$SKILLS" november)
cat > "$S/scripts/parse-args.sh" <<'EOF'
#!/bin/sh
PARSED=$("$SCRIPT_DIR/parse-flags.sh" auto:bool -- "$INPUT") || exit 64
EOF
cat > "$S/scripts/reference-context.sh" <<'EOF'
#!/bin/sh
eval "$("$HERE/parse-flags.sh" pr:value issue:value no-context:bool -- "$INPUT")"
EOF
cat > "$S/HOW_TO_USE.md" <<'EOF'
# november 利用ガイド

## フラグ一覧

| フラグ | 機能 |
|---|---|
| `--auto` | 無人完走 |
EOF
out=$("$SCRIPT" "$SKILLS" 2>&1)
rc=$?
assert_eq "exit 0" "0" "$rc"
assert_not_contains "内部ヘルパの引数は拾わない" "--pr" "$out"

# --- case 13: skills ディレクトリ不在は実行エラー ---
echo "case 13: skills ディレクトリ不在"
out=$("$SCRIPT" "/nonexistent-skills-dir-for-test" 2>&1)
rc=$?
assert_eq "exit 1" "1" "$rc"
assert_contains "エラーメッセージ" "skills ディレクトリが見つからない" "$out"

echo
printf 'total: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
