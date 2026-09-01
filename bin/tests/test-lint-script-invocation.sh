#!/bin/bash
# bin/lint-script-invocation.sh のユニットテスト。
# 実リポジトリの skills/ には依存せず、mktemp -d で作った隔離 sandbox に
# 疑似 skill ディレクトリを組み立てて検出パターンを検証する。
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
SCRIPT="$REPO_ROOT/bin/lint-script-invocation.sh"

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
    local _name=$1 _expected=$2 _actual=$3
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
    local _name=$1 _needle=$2 _haystack=$3
    if printf '%s' "$_haystack" | grep -qF -e "$_needle"; then
        printf '  PASS: %s\n' "$_name"
        pass=$((pass + 1))
    else
        printf '  FAIL: %s (期待する部分文字列が出力に含まれない: %s)\n' "$_name" "$_needle"
        printf '    actual: %s\n' "$_haystack"
        fail=$((fail + 1))
    fi
}

# $S に sandbox の skills/ パスを設定する。
# `S=$(new_sandbox)` のように command substitution で呼ぶと SANDBOXES への追記が
# サブシェルに閉じて cleanup が効かなくなるため、親シェルで直接呼んで代入する。
S=""
new_sandbox() {
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/test-lint-script-invocation.XXXXXXXX")
    SANDBOXES+=("$d")
    mkdir -p "$d/skills"
    S="$d/skills"
}

echo "== bin/lint-script-invocation.sh =="

# --- 1. 新記法のみ: PASS ---
new_sandbox
mkdir -p "$S/alpha/references"
cat > "$S/alpha/SKILL.md" <<'MD'
# alpha
eval "$("$SKILL_DIR/scripts/parse-args.sh" "$USER_INPUT")"
MD
cat > "$S/alpha/references/x.md" <<'MD'
`"$SKILL_DIR/scripts/foo.sh"` に委譲する。
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "新記法のみなら exit 0" "0" "$RC"
assert_contains "PASS が出力される" "lint-script-invocation: PASS" "$OUT"

# --- 2. SKILL.md のコードフェンス内に ./scripts/: FAIL ---
new_sandbox
mkdir -p "$S/beta"
cat > "$S/beta/SKILL.md" <<'MD'
# beta
```sh
./scripts/preflight.sh --input-kind issue
```
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "コードフェンス内の ./scripts/ で exit 1" "1" "$RC"
assert_contains "違反ファイルが報告される" "skills/beta/SKILL.md" "$OUT"

# --- 3. 散文中の言及のみでも FAIL ---
new_sandbox
mkdir -p "$S/gamma"
cat > "$S/gamma/SKILL.md" <<'MD'
# gamma
判定ルールの真実源は `./scripts/branch-guard.sh` header。
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "散文中の言及のみでも exit 1" "1" "$RC"
assert_contains "行番号つきで報告される" "skills/gamma/SKILL.md:2" "$OUT"

# --- 4. references/ 配下も走査対象 ---
new_sandbox
mkdir -p "$S/delta/references"
cat > "$S/delta/SKILL.md" <<'MD'
# delta
MD
cat > "$S/delta/references/create.md" <<'MD'
`./scripts/parse-args.sh` を実行する。
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "references/ 配下でも exit 1" "1" "$RC"
assert_contains "references の違反が報告される" "skills/delta/references/create.md" "$OUT"

# --- 5. HOW_TO_USE.md も走査対象 ---
new_sandbox
mkdir -p "$S/epsilon"
cat > "$S/epsilon/SKILL.md" <<'MD'
# epsilon
MD
cat > "$S/epsilon/HOW_TO_USE.md" <<'MD'
手動実行: `./scripts/render.sh`
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "HOW_TO_USE.md でも exit 1" "1" "$RC"
assert_contains "HOW_TO_USE の違反が報告される" "skills/epsilon/HOW_TO_USE.md" "$OUT"

# --- 6. md 以外 (scripts/*.sh のコメント等) は対象外 ---
new_sandbox
mkdir -p "$S/zeta/scripts"
cat > "$S/zeta/SKILL.md" <<'MD'
# zeta
MD
cat > "$S/zeta/scripts/parse-args.sh" <<'SH'
#!/bin/sh
# usage: ./scripts/parse-args.sh "$USER_INPUT"
SH
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "md 以外は対象外なので exit 0" "0" "$RC"

# --- 7. skills ディレクトリ不在は実行エラー ---
new_sandbox
OUT=$(sh "$SCRIPT" "$S/no-such-dir" 2>&1); RC=$?
assert_eq "skills ディレクトリ不在で exit 1" "1" "$RC"
assert_contains "不在メッセージが出る" "skills ディレクトリが見つからない" "$OUT"

# --- 8. cd は検出しない (例外規則を持たないことの確認) ---
new_sandbox
mkdir -p "$S/eta"
cat > "$S/eta/SKILL.md" <<'MD'
# eta
```sh
cd "$REPO_ROOT"
"$SKILL_DIR/scripts/run.sh"
```
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "cd 単体は検出せず exit 0" "0" "$RC"

# --- 9. 読み取り不能な md は「違反なし」ではなく実行エラーとして扱う ---
# root は permission を無視して読めてしまうため、非 root のときだけ検証する。
if [ "$(id -u)" -ne 0 ]; then
    new_sandbox
    mkdir -p "$S/theta"
    cat > "$S/theta/SKILL.md" <<'MD'
# theta
MD
    chmod 000 "$S/theta/SKILL.md"
    OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
    chmod 644 "$S/theta/SKILL.md"
    assert_eq "読み取り失敗を PASS にせず exit 1" "1" "$RC"
    assert_contains "実行エラーとして報告される" "走査中に実行エラーが発生した" "$OUT"
else
    echo "  SKIP: 読み取り失敗ケース (root 実行のため)"
fi

# --- 10. `./` 無しのインタプリタ前置呼び出し: FAIL ---
# `node scripts/foo.mjs` / `bash scripts/foo.sh` / `eval "$(sh scripts/parse-args.sh ...)"`
new_sandbox
mkdir -p "$S/iota"
cat > "$S/iota/SKILL.md" <<'MD'
# iota
```sh
node scripts/fetch-page.mjs "<URL>"
bash scripts/enumerate-md.sh "$TARGET_DIR"
eval "$(sh scripts/parse-args.sh "$USER_INPUT")"
timeout 90 node scripts/extract-text.mjs --in "$INPUT_PATH"
OUTPUT_PATH=$(sh scripts/resolve-output-path.sh "$TARGET_DIR")
```
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "./ 無しのインタプリタ前置で exit 1" "1" "$RC"
assert_contains "node 前置が報告される" "skills/iota/SKILL.md:3" "$OUT"
assert_contains "bash 前置が報告される" "skills/iota/SKILL.md:4" "$OUT"
# テスト名に literal の $( を含めるため単一引用符のまま扱う
# shellcheck disable=SC2016
assert_contains 'eval "$(sh ...)" が報告される' "skills/iota/SKILL.md:5" "$OUT"
assert_contains "timeout N 前置が報告される" "skills/iota/SKILL.md:6" "$OUT"
# shellcheck disable=SC2016
assert_contains 'VAR=$(sh ...) が報告される' "skills/iota/SKILL.md:7" "$OUT"

# --- 11. `./` 無しの行頭直接実行: FAIL ---
new_sandbox
mkdir -p "$S/kappa"
cat > "$S/kappa/SKILL.md" <<'MD'
# kappa
```sh
scripts/preflight.sh --input-kind issue
scripts/import.sh input.csv
scripts/render.sh
timeout 90 scripts/slow.sh
OUT=$(scripts/collect.sh)
scripts/first.sh && scripts/next.sh
if scripts/validate.sh "$CSV"; then :; fi
! scripts/check.sh
FOO=bar scripts/env-prefixed.sh
printf x | scripts/filter.sh
sleep 1 & scripts/background.sh
( scripts/in-subshell.sh )
scripts/foo.sh; echo done
```
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "行頭の直接実行で exit 1" "1" "$RC"
assert_contains "記号始まりの引数が報告される" "skills/kappa/SKILL.md:3" "$OUT"
assert_contains "通常文字始まりの引数も報告される" "skills/kappa/SKILL.md:4" "$OUT"
assert_contains "引数なしの行末も報告される" "skills/kappa/SKILL.md:5" "$OUT"
assert_contains "timeout N + bare が報告される" "skills/kappa/SKILL.md:6" "$OUT"
# shellcheck disable=SC2016
assert_contains 'VAR=$(bare) が報告される' "skills/kappa/SKILL.md:7" "$OUT"
assert_contains "&& の右辺 bare が報告される" "skills/kappa/SKILL.md:8" "$OUT"
assert_contains "if 直後の bare が報告される" "skills/kappa/SKILL.md:9" "$OUT"
assert_contains "! 直後の bare が報告される" "skills/kappa/SKILL.md:10" "$OUT"
assert_contains "環境変数代入前置の bare が報告される" "skills/kappa/SKILL.md:11" "$OUT"
assert_contains "パイプ右辺の bare が報告される" "skills/kappa/SKILL.md:12" "$OUT"
assert_contains "& 直後の bare が報告される" "skills/kappa/SKILL.md:13" "$OUT"
assert_contains "サブシェル内の bare が報告される" "skills/kappa/SKILL.md:14" "$OUT"
assert_contains "引数なし + 区切り直付けが報告される" "skills/kappa/SKILL.md:15" "$OUT"

# --- 11b. markdown 表セルのパスはパイプ文脈と誤認しない: PASS ---
new_sandbox
mkdir -p "$S/kappa2"
cat > "$S/kappa2/SKILL.md" <<'MD'
# kappa2

| ファイル | 責務 |
| --- | --- |
| scripts/parse-args.sh | 引数解析 |
| scripts/render.mjs | 描画 |
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "表セルのパスは検出せず exit 0" "0" "$RC"

# --- 12. `./` 無しの散文中の言及: PASS ---
# 実行文ではない言及まで拾うと、SSOT 注記や責務説明が軒並み違反になる。
new_sandbox
mkdir -p "$S/lambda/references"
cat > "$S/lambda/SKILL.md" <<'MD'
# lambda
ユーザー入力を `scripts/parse-args.sh` に委譲する:
> **フラグ・default の真実源 (SSOT) は `scripts/parse-flags.sh`** です。
- 入力の分類は `scripts/classify-input.sh` が行う。
MD
cat > "$S/lambda/references/note.md" <<'MD'
scripts/refresh-data.sh がこの出力とこの表の差分を出す。
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "散文中の言及は検出せず exit 0" "0" "$RC"

# --- 13. HOW_TO_USE の人間向け手動実行手順 (リポジトリ相対): PASS ---
new_sandbox
mkdir -p "$S/mu"
cat > "$S/mu/SKILL.md" <<'MD'
# mu
MD
cat > "$S/mu/HOW_TO_USE.md" <<'MD'
初回のみ手動で実行しておく:

```sh
sh skills/mu/scripts/setup.sh
node skills/mu/scripts/crawl.mjs "<URL>"
```
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "リポジトリ相対の手動実行手順は検出せず exit 0" "0" "$RC"

# --- 14. 新記法 (`$SKILL_DIR` 付き) は node 前置でも PASS ---
new_sandbox
mkdir -p "$S/nu"
cat > "$S/nu/SKILL.md" <<'MD'
# nu
```sh
node "$SKILL_DIR/scripts/fetch-page.mjs" "<URL>"
timeout 90 node "$SKILL_DIR/scripts/extract-text.mjs" --in "$INPUT_PATH"
"$SKILL_DIR/scripts/preflight.sh" --input-kind issue
```
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "\$SKILL_DIR 付きは検出せず exit 0" "0" "$RC"

# --- 15. node_modules/ 配下の md は走査対象外 ---
# skill が auto-install する外部パッケージの README まで拾うと制御不能になる。
new_sandbox
mkdir -p "$S/xi/scripts/node_modules/some-pkg"
cat > "$S/xi/SKILL.md" <<'MD'
# xi
MD
cat > "$S/xi/scripts/node_modules/some-pkg/README.md" <<'MD'
```sh
node scripts/bench.js
./scripts/build.sh
```
MD
OUT=$(sh "$SCRIPT" "$S" 2>&1); RC=$?
assert_eq "node_modules 配下は対象外なので exit 0" "0" "$RC"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
