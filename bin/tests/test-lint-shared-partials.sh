#!/bin/bash
# bin/lint-shared-partials.mjs のユニットテスト。
# 隔離 sandbox に partial / 埋め込み先 / マニフェストを作り、同期 OK・drift・
# 未登録マーカー(登録漏れ)の各ケースを検証する。
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
SCRIPT="$REPO_ROOT/bin/lint-shared-partials.mjs"

pass=0
fail=0
SANDBOXES=()

cleanup() {
    if [ "${#SANDBOXES[@]}" -gt 0 ]; then
        for d in "${SANDBOXES[@]}"; do
            [ -d "$d" ] && rm -rf "$d"
        done
    fi
}
trap cleanup EXIT

assert_eq() {
    if [ "$2" = "$3" ]; then
        printf '  PASS: %s\n' "$1"
        pass=$((pass + 1))
    else
        printf '  FAIL: %s (expected: %s, actual: %s)\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    if printf '%s' "$3" | grep -qF -- "$2"; then
        printf '  PASS: %s\n' "$1"
        pass=$((pass + 1))
    else
        printf '  FAIL: %s (期待する部分文字列が出力に無い: %s)\n' "$1" "$2"
        fail=$((fail + 1))
    fi
}

new_sandbox() {
    _dir=$(mktemp -d)
    SANDBOXES+=("$_dir")
    mkdir -p "$_dir/skills/a" "$_dir/skills/b"
    printf '<!-- @partial:demo start -->\nhello\n<!-- @partial:demo end -->\n' > "$_dir/demo.md"
    printf '# a\n\n<!-- @partial:demo start -->\nhello\n<!-- @partial:demo end -->\n' > "$_dir/skills/a/SKILL.md"
    printf '%s\t%s\n' "$_dir/demo.md" "$_dir/skills/a/SKILL.md" > "$_dir/manifest.tsv"
    printf '%s\n' "$_dir"
}

# case 1: 登録済み・byte 同一なら PASS
sb=$(new_sandbox)
OUT=$(node "$SCRIPT" "$sb/manifest.tsv" "$sb/skills" 2>&1); RC=$?
assert_eq "case1: 登録済みで exit 0" "0" "$RC"
assert_contains "case1: PASS メッセージ" "PASS" "$OUT"

# case 2: 未登録のマーカーがあると fail
sb=$(new_sandbox)
printf '# b\n\n<!-- @partial:demo start -->\nhello\n<!-- @partial:demo end -->\n' > "$sb/skills/b/SKILL.md"
OUT=$(node "$SCRIPT" "$sb/manifest.tsv" "$sb/skills" 2>&1); RC=$?
assert_eq "case2: 未登録マーカーで exit 1" "1" "$RC"
assert_contains "case2: 未登録の埋め込み先がエラーに出る" "$sb/skills/b/SKILL.md" "$OUT"
assert_contains "case2: 未登録の文言" "未登録" "$OUT"

# case 3: 別 id の未登録マーカーも検出する(同じファイルに登録済み id があっても)
sb=$(new_sandbox)
printf '<!-- @partial:other start -->\nx\n<!-- @partial:other end -->\n' >> "$sb/skills/a/SKILL.md"
OUT=$(node "$SCRIPT" "$sb/manifest.tsv" "$sb/skills" 2>&1); RC=$?
assert_eq "case3: 別 id の未登録で exit 1" "1" "$RC"
assert_contains "case3: id がエラーに出る" "[other]" "$OUT"

# case 4: drift は従来どおり検出する
sb=$(new_sandbox)
printf '# a\n\n<!-- @partial:demo start -->\nchanged\n<!-- @partial:demo end -->\n' > "$sb/skills/a/SKILL.md"
OUT=$(node "$SCRIPT" "$sb/manifest.tsv" "$sb/skills" 2>&1); RC=$?
assert_eq "case4: drift で exit 1" "1" "$RC"
assert_contains "case4: drift 検出" "drift" "$OUT"

# case 5: スキャン対象を渡さない(マニフェスト上書きのみ)ときは登録漏れを検査しない
sb=$(new_sandbox)
printf '# b\n\n<!-- @partial:demo start -->\nhello\n<!-- @partial:demo end -->\n' > "$sb/skills/b/SKILL.md"
OUT=$(node "$SCRIPT" "$sb/manifest.tsv" 2>&1); RC=$?
assert_eq "case5: スキャンなしで exit 0" "0" "$RC"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
