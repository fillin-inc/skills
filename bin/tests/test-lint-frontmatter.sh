#!/bin/bash
# bin/lint-frontmatter.sh の echo/assert テスト。
# 各 fixture は `<test-root>/<name>/SKILL.md` 形式で配置し、`<test-root>` に cd してから
# lint を実行する。これにより `find . -name SKILL.md` で見つかる SKILL.md の親 dir 名と
# frontmatter の name field を一致比較できる（リポジトリ内の他 SKILL.md も巻き込まない）。
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../lint-frontmatter.sh"

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

run_in() {
    (cd "$1" && "$SCRIPT" >/dev/null 2>&1)
}

# 一意な test root を作って fixture の `<name>/SKILL.md` を置くヘルパ
new_root() {
    mktemp -d "$TMPROOT/case.XXXXXX"
}

# case 1: SKILL.md が一つもない → exit 0
ROOT=$(new_root)
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case1: no SKILL.md => exit 0" "0" "$ec"

# case 2: 正常 frontmatter → exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/ok"
cat >"$ROOT/ok/SKILL.md" <<'EOF'
---
name: ok
description: a normal description without colon-space
license: MIT
---

body
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case2: well-formed => exit 0" "0" "$ec"

# case 3: unquoted で `[` 始まり → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/bracket"
cat >"$ROOT/bracket/SKILL.md" <<'EOF'
---
name: bracket
description: x
allowed-tools: [Read, Edit]
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case3: unquoted [ => exit 1" "1" "$ec"

# case 4: unquoted で ": " を含む → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/colon"
cat >"$ROOT/colon/SKILL.md" <<'EOF'
---
name: colon
description: foo: bar
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case4: unquoted ': ' => exit 1" "1" "$ec"

# case 5: ダブルクォートで囲まれた `[` 値 → exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/quoted-bracket"
cat >"$ROOT/quoted-bracket/SKILL.md" <<'EOF'
---
name: quoted-bracket
description: x
license: MIT
allowed-tools: "[Read, Edit]"
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case5: double-quoted [ => exit 0" "0" "$ec"

# case 6: シングルクォートで囲まれた ": " 値 → exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/quoted-colon"
cat >"$ROOT/quoted-colon/SKILL.md" <<'EOF'
---
name: quoted-colon
description: 'foo: bar'
license: MIT
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case6: single-quoted ': ' => exit 0" "0" "$ec"

# case 7: frontmatter 外の ": " は無視される（本文に書く）→ exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/outside"
cat >"$ROOT/outside/SKILL.md" <<'EOF'
---
name: outside
description: clean value
license: MIT
---

# 本文

key: value within body should not trigger
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case7: ': ' outside frontmatter => exit 0" "0" "$ec"

# case 8: 複数 SKILL.md の中に 1 つ NG が混じる → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/a" "$ROOT/b"
cat >"$ROOT/a/SKILL.md" <<'EOF'
---
name: a
description: clean
license: MIT
---
EOF
cat >"$ROOT/b/SKILL.md" <<'EOF'
---
name: b
description: foo: bar
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case8: any one bad => exit 1" "1" "$ec"

# case 9: name が directory 名と一致しない → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/parent-dir"
cat >"$ROOT/parent-dir/SKILL.md" <<'EOF'
---
name: different-name
description: x
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case9: name != dirname => exit 1" "1" "$ec"

# case 10: name が kebab-case ではない (underscore) → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/name_invalid"
cat >"$ROOT/name_invalid/SKILL.md" <<'EOF'
---
name: name_invalid
description: x
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case10: name with underscore => exit 1" "1" "$ec"

# case 11: name が連続ハイフン → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/double--hyphen"
cat >"$ROOT/double--hyphen/SKILL.md" <<'EOF'
---
name: double--hyphen
description: x
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case11: name with consecutive hyphens => exit 1" "1" "$ec"

# case 12: name が先頭ハイフン → exit 1 (directory も先頭ハイフンに揃える)
ROOT=$(new_root)
mkdir -p "$ROOT/-leading"
cat >"$ROOT/-leading/SKILL.md" <<'EOF'
---
name: -leading
description: x
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case12: name with leading hyphen => exit 1" "1" "$ec"

# case 13: description が空 → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/desc-empty"
cat >"$ROOT/desc-empty/SKILL.md" <<'EOF'
---
name: desc-empty
description:
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case13: description empty => exit 1" "1" "$ec"

# case 14: description が 1024 超 → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/desc-long"
{
    printf -- '---\n'
    printf 'name: desc-long\n'
    # 1025 chars (a x 1025) で 1024 上限超
    printf 'description: '
    awk 'BEGIN { for (i = 0; i < 1025; i++) printf "a"; print "" }'
    printf -- '---\n'
} >"$ROOT/desc-long/SKILL.md"
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case14: description > 1024 chars => exit 1" "1" "$ec"

# case 15: 仕様外フィールド (argument-hint 以外) は警告で exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/unknown-field"
cat >"$ROOT/unknown-field/SKILL.md" <<'EOF'
---
name: unknown-field
description: x
license: MIT
unknown-field: hello
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case15: unknown field => exit 0 (warn only)" "0" "$ec"

# case 16: argument-hint は許可リストに含まれる → exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/arg-hint"
cat >"$ROOT/arg-hint/SKILL.md" <<'EOF'
---
name: arg-hint
description: x
license: MIT
argument-hint: "[--auto]"
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case16: argument-hint allowed => exit 0" "0" "$ec"

# case 17: name field 欠落 → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/no-name"
cat >"$ROOT/no-name/SKILL.md" <<'EOF'
---
description: x
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case17: missing name field => exit 1" "1" "$ec"

# case 18: description field 欠落 → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/no-desc"
cat >"$ROOT/no-desc/SKILL.md" <<'EOF'
---
name: no-desc
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case18: missing description field => exit 1" "1" "$ec"

# case 19: description が YAML ブロックスカラー (pipe) で始まる → exit 1
# 単一行リーダーでは後続のインデント行を含めた実長を取れず、長さ検証が骨抜きになるため。
ROOT=$(new_root)
mkdir -p "$ROOT/desc-block-pipe"
cat >"$ROOT/desc-block-pipe/SKILL.md" <<'EOF'
---
name: desc-block-pipe
description: |
  multi-line description that bypasses the length check
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq 'case19: description with block scalar (pipe) => exit 1' "1" "$ec"

# case 20: description が YAML ブロックスカラー (folded) で始まる → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/desc-block-gt"
cat >"$ROOT/desc-block-gt/SKILL.md" <<'EOF'
---
name: desc-block-gt
description: >
  folded multi-line description that also bypasses the length check
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq 'case20: description with block scalar (folded) => exit 1' "1" "$ec"

# case 21: 英字以外で始まる仕様外フィールド (_custom) も警告対象になる → exit 0 (警告のみ)
# 受け入れ条件「frontmatter フィールドが許可リストに収まる」を満たすため、key 抽出を
# 英字始まりに限定せず広く拾ったうえで allowlist 照合する。
ROOT=$(new_root)
mkdir -p "$ROOT/unknown-underscore"
cat >"$ROOT/unknown-underscore/SKILL.md" <<'EOF'
---
name: unknown-underscore
description: x
license: MIT
_custom: hello
---
EOF
set +e
(cd "$ROOT" && "$SCRIPT" >/dev/null 2>"$TMPROOT/stderr.txt")
ec=$?
set -e
assert_eq "case21: underscore-leading unknown field => exit 0" "0" "$ec"
# 警告メッセージが stderr に出ていることも確認
if grep -q "_custom" "$TMPROOT/stderr.txt"; then
    printf '  PASS: case21b: warning mentions _custom field\n'
    pass=$((pass + 1))
else
    printf '  FAIL: case21b: warning mentions _custom field\n'
    cat "$TMPROOT/stderr.txt" >&2
    fail=$((fail + 1))
fi

# case 22: license field 欠落 → exit 1（AGENTS.md の方針でリポジトリ必須化）
ROOT=$(new_root)
mkdir -p "$ROOT/no-license"
cat >"$ROOT/no-license/SKILL.md" <<'EOF'
---
name: no-license
description: x
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case22: missing license field => exit 1" "1" "$ec"

# case 23: license 値が空 → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/empty-license"
cat >"$ROOT/empty-license/SKILL.md" <<'EOF'
---
name: empty-license
description: x
license:
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case23: empty license value => exit 1" "1" "$ec"

# case 24: license 値が quoted で複雑な文字列 → exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/license-quoted"
cat >"$ROOT/license-quoted/SKILL.md" <<'EOF'
---
name: license-quoted
description: x
license: MIT
---
EOF
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case24: quoted complex license => exit 0" "0" "$ec"

# case 25: 本文 500 行ちょうど → exit 0
ROOT=$(new_root)
mkdir -p "$ROOT/body-500"
{
    printf -- '---\n'
    printf 'name: body-500\n'
    printf 'description: x\n'
    printf 'license: MIT\n'
    printf -- '---\n'
    awk 'BEGIN { for (i = 0; i < 500; i++) print "body" }'
} >"$ROOT/body-500/SKILL.md"
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case25: body == 500 lines => exit 0" "0" "$ec"

# case 26: 本文 501 行 → exit 1
ROOT=$(new_root)
mkdir -p "$ROOT/body-501"
{
    printf -- '---\n'
    printf 'name: body-501\n'
    printf 'description: x\n'
    printf 'license: MIT\n'
    printf -- '---\n'
    awk 'BEGIN { for (i = 0; i < 501; i++) print "body" }'
} >"$ROOT/body-501/SKILL.md"
set +e
run_in "$ROOT"
ec=$?
set -e
assert_eq "case26: body == 501 lines => exit 1" "1" "$ec"

echo ""
printf 'passed: %d, failed: %d\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
